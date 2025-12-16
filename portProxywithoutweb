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
	// 修改了日志文字，避免误解
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

	remoteConn, err := net.DialTimeout("tcp", remoteAddr, 5*time.Second)
	if err != nil {
		return
	}
	defer remoteConn.Close()

	if tcp, ok := clientConn.(*net.TCPConn); ok { _ = tcp.SetNoDelay(true) }
	if tcp, ok := remoteConn.(*net.TCPConn); ok { _ = tcp.SetNoDelay(true) }

	go io.Copy(remoteConn, clientConn)
	io.Copy(clientConn, remoteConn)
}
