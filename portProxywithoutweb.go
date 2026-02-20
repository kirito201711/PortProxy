package main

import (
	"encoding/json"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"time"
)

type Config struct {
	Local  string `json:"local"`
	Remote string `json:"remote"`
}

func main() {
	exePath, _ := os.Executable()
	configPath := filepath.Join(filepath.Dir(exePath), "config.json")

	file, err := os.ReadFile(configPath)
	if err != nil {
		log.Fatalf("读取配置失败: %v", err)
	}

	var rules []Config
	if err := json.Unmarshal(file, &rules); err != nil {
		log.Fatalf("JSON格式错误: %v", err)
	}

	for _, rule := range rules {
		go runProxy(rule.Local, rule.Remote)
	}

	select {}
}

func runProxy(local, remote string) {
	listener, err := net.Listen("tcp", local)
	if err != nil {
		log.Printf("端口占用或失败 [%s]: %v", local, err)
		return
	}
	log.Printf("转发服务就绪: 本机[%s] >>> 目标[%s]", local, remote)

	for {
		clientConn, err := listener.Accept()
		if err != nil {
			continue
		}
		go handleConn(clientConn, remote)
	}
}

func handleConn(clientConn net.Conn, remoteAddr string) {
	defer clientConn.Close()

	// 1. 设置客户端连接 Keep-Alive
	if tcp, ok := clientConn.(*net.TCPConn); ok {
		_ = tcp.SetNoDelay(true)
		_ = tcp.SetKeepAlive(true)
		_ = tcp.SetKeepAlivePeriod(30 * time.Second)
	}

	// 2. 拨号目标地址，自带保活与超时
	dialer := &net.Dialer{
		Timeout:   10 * time.Second,
		KeepAlive: 30 * time.Second,
	}
	remoteConn, err := dialer.Dial("tcp", remoteAddr)
	if err != nil {
		return
	}
	defer remoteConn.Close()

	if tcp, ok := remoteConn.(*net.TCPConn); ok {
		_ = tcp.SetNoDelay(true)
	}

	// 3. 核心修复：引入 errChan 实现双端联动关闭机制
	errChan := make(chan error, 2)

	// 协程1：远程 -> 客户端
	go func() {
		_, err := io.Copy(clientConn, remoteConn)
		errChan <- err
	}()

	// 协程2：客户端 -> 远程
	go func() {
		_, err := io.Copy(remoteConn, clientConn)
		errChan <- err
	}()

	// 阻塞等待：无论哪一端断开、报错或者被 Keep-Alive 掐断，都会立刻放行
	<-errChan

	// 放行后触发函数结尾，由双层 defer 去销毁双方的连接 Socket
	// 完美释放不会残留任何 ESTAB 状态
	clientConn.Close()
	remoteConn.Close()
	<-errChan // 回收最后一个协程的信号
}
