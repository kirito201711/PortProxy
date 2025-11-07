package main

import (
        "crypto/rand"
        "encoding/hex"
        "encoding/json"
        "flag"
        "fmt"
        "golang.org/x/crypto/bcrypt"
        "io"
        "log"
        "net"
        "net/http"
        "os"
        "path/filepath"
        "strings"
        "sync"
        "time"
)

// --- 数据结构 ---

type Config struct {
        AdminAddr    string `json:"admin_addr"`
        PasswordHash []byte `json:"password_hash"`
}

type ForwardRule struct {
        Name        string          `json:"name"`
        LocalAddr   string          `json:"local_addr"`
        RemoteAddr  string          `json:"remote_addr"`
        listener    net.Listener    `json:"-"`
        connsMu     sync.Mutex      `json:"-"`
        activeConns map[net.Conn]struct{} `json:"-"`
}

type UpdateRuleRequest struct {
        OriginalLocalAddr string `json:"original_local_addr"`
        Name              string `json:"name"`
        LocalAddr         string `json:"local_addr"`
        RemoteAddr        string `json:"remote_addr"`
}

type ProxyManager struct {
        mu        sync.RWMutex
        rules     map[string]*ForwardRule
        rulesPath string
}

var sessionStore = struct {
        sync.RWMutex
        sessions map[string]time.Time
}{sessions: make(map[string]time.Time)}

const sessionCookieName = "tcp_proxy_session"
const sessionDuration = 24 * time.Hour

var globalConfig Config

// --- 主程序入口 ---
func main() {
        adminAddrFlag := flag.String("admin", "", "Web管理面板的监听地址和端口 (例如: :9090)")
        passwordFlag := flag.String("password", "", "设置Web面板的初始密码 (仅在首次启动时需要)")
        flag.Parse()

        exePath, err := os.Executable()
        if err != nil {
                log.Fatalf("无法获取可执行文件路径: %v", err)
        }
        exeDir := filepath.Dir(exePath)
        configPath := filepath.Join(exeDir, "config.json")
        rulesPath := filepath.Join(exeDir, "rules.json")

        if _, err := os.Stat(configPath); os.IsNotExist(err) {
                if *adminAddrFlag == "" || *passwordFlag == "" {
                        log.Fatalf("错误: 配置文件 'config.json' 不存在。\n请使用 -admin=<:端口> 和 -password=<你的密码> 参数进行首次初始化。")
                }
                initializeConfig(configPath, *adminAddrFlag, *passwordFlag)
        } else {
                loadConfig(configPath)
        }

        manager := NewProxyManager(rulesPath)
        manager.loadRules()

        server := &http.Server{
                Addr:    globalConfig.AdminAddr,
                Handler: webHandlers(manager, exeDir),
        }

        log.Printf("零拷贝 TCP 转发器已启动...")

        displayHost, displayPort, _ := net.SplitHostPort(globalConfig.AdminAddr)
        if displayHost == "" || displayHost == "0.0.0.0" {
                displayHost = getPreferredIP()
        }
        log.Printf("Web 管理面板正在监听: http://%s:%s", displayHost, displayPort)

        if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
                log.Fatalf("启动 Web 管理面板失败: %v", err)
        }
}

// --- Helper & Config Functions ---
func getPreferredIP() string {
        interfaces, err := net.Interfaces()
        if err != nil {
                return "127.0.0.1"
        }
        for _, iface := range interfaces {
                if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
                        continue
                }
                addrs, err := iface.Addrs()
                if err != nil {
                        continue
                }
                for _, addr := range addrs {
                        var ip net.IP
                        switch v := addr.(type) {
                        case *net.IPNet:
                                ip = v.IP
                        case *net.IPAddr:
                                ip = v.IP
                        }
                        if ip == nil || ip.IsLoopback() {
                                continue
                        }
                        ip = ip.To4()
                        if ip == nil {
                                continue
                        }
                        return ip.String()
                }
        }
        return "127.0.0.1"
}

func initializeConfig(path, addr, password string) {
        hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
        if err != nil {
                log.Fatalf("无法哈希密码: %v", err)
        }
        globalConfig = Config{
                AdminAddr:    addr,
                PasswordHash: hash,
        }
        configData, _ := json.MarshalIndent(globalConfig, "", "  ")
        if err := os.WriteFile(path, configData, 0600); err != nil {
                log.Fatalf("无法写入初始化配置文件: %v", err)
        }
}

func loadConfig(path string) {
        configData, err := os.ReadFile(path)
        if err != nil {
                log.Fatalf("无法读取配置文件 %s: %v", path, err)
        }
        if err := json.Unmarshal(configData, &globalConfig); err != nil {
                log.Fatalf("解析配置文件 %s 失败: %v", path, err)
        }
        // 日志已删除: log.Printf("已从 %s 加载配置", path)
}

// --- Web & Auth Handlers ---
func authMiddleware(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                cookie, err := r.Cookie(sessionCookieName)
                if err != nil {
                        http.Redirect(w, r, "/login", http.StatusFound)
                        return
                }
                sessionStore.RLock()
                expiry, ok := sessionStore.sessions[cookie.Value]
                sessionStore.RUnlock()
                if !ok || time.Now().After(expiry) {
                        http.Redirect(w, r, "/login", http.StatusFound)
                        return
                }
                next.ServeHTTP(w, r)
        })
}

func loginHandler(w http.ResponseWriter, r *http.Request, loginPath string) {
        if r.Method == http.MethodGet {
                http.ServeFile(w, r, loginPath)
                return
        }
        if r.Method == http.MethodPost {
                password := r.FormValue("password")
                err := bcrypt.CompareHashAndPassword(globalConfig.PasswordHash, []byte(password))
                if err != nil {
                        http.Error(w, "密码错误", http.StatusUnauthorized)
                        return
                }
                tokenBytes := make([]byte, 32)
                _, _ = rand.Read(tokenBytes)
                sessionToken := hex.EncodeToString(tokenBytes)
                expiry := time.Now().Add(sessionDuration)
                sessionStore.Lock()
                sessionStore.sessions[sessionToken] = expiry
                sessionStore.Unlock()
                http.SetCookie(w, &http.Cookie{
                        Name:     sessionCookieName,
                        Value:    sessionToken,
                        Expires:  expiry,
                        HttpOnly: true,
                        Path:     "/",
                })
                http.Redirect(w, r, "/", http.StatusFound)
        }
}

func logoutHandler(w http.ResponseWriter, r *http.Request) {
        cookie, err := r.Cookie(sessionCookieName)
        if err == nil {
                sessionStore.Lock()
                delete(sessionStore.sessions, cookie.Value)
                sessionStore.Unlock()
        }
        http.SetCookie(w, &http.Cookie{
                Name:   sessionCookieName,
                Value:  "",
                MaxAge: -1,
                Path:   "/",
        })
        http.Redirect(w, r, "/login", http.StatusFound)
}

func webHandlers(pm *ProxyManager, exeDir string) http.Handler {
        indexPath := filepath.Join(exeDir, "index.html")
        loginPath := filepath.Join(exeDir, "login.html")
        mux := http.NewServeMux()
        protectedMux := http.NewServeMux()
        protectedMux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
                if r.URL.Path != "/" {
                        http.NotFound(w, r)
                        return
                }
                http.ServeFile(w, r, indexPath)
        })
        protectedMux.HandleFunc("/api/rules", pm.apiRulesHandler)
        protectedMux.HandleFunc("/logout", logoutHandler)
        mux.HandleFunc("/login", func(w http.ResponseWriter, r *http.Request) {
                loginHandler(w, r, loginPath)
        })
        mux.Handle("/", authMiddleware(protectedMux))
        return mux
}

// --- ProxyManager Methods ---

func NewProxyManager(rulesPath string) *ProxyManager {
        return &ProxyManager{
                rules:     make(map[string]*ForwardRule),
                rulesPath: rulesPath,
        }
}

func (pm *ProxyManager) loadRules() {
        data, err := os.ReadFile(pm.rulesPath)
        if err != nil {
                // 日志已删除: log.Printf("无法读取规则文件 %s: %v", pm.rulesPath, err)
                return
        }
        var rulesToLoad []*ForwardRule
        if err := json.Unmarshal(data, &rulesToLoad); err != nil {
                // 日志已删除: log.Printf("解析规则文件 %s 失败: %v", pm.rulesPath, err)
                return
        }
        // 日志已删除: log.Printf("从 %s 加载 %d 条规则...", pm.rulesPath, len(rulesToLoad))
        for _, rule := range rulesToLoad {
                if _, err := pm.AddRule(rule.Name, rule.LocalAddr, rule.RemoteAddr); err != nil {
                        // 日志已删除: log.Printf("加载规则 %s -> %s 失败: %v", rule.LocalAddr, rule.RemoteAddr, err)
                }
        }
}

func (pm *ProxyManager) saveRules() error {
        pm.mu.RLock()
        rulesToSave := make([]*ForwardRule, 0, len(pm.rules))
        for _, rule := range pm.rules {
                rulesToSave = append(rulesToSave, &ForwardRule{Name: rule.Name, LocalAddr: rule.LocalAddr, RemoteAddr: rule.RemoteAddr})
        }
        pm.mu.RUnlock() // Release lock before I/O

        data, err := json.MarshalIndent(rulesToSave, "", "  ")
        if err != nil {
                return fmt.Errorf("序列化规则失败: %v", err)
        }
        return os.WriteFile(pm.rulesPath, data, 0644)
}

func (pm *ProxyManager) AddRule(name, localAddr, remoteAddr string) (*ForwardRule, error) {
        if !strings.Contains(localAddr, ":") {
                localAddr = "0.0.0.0:" + localAddr
        }

        pm.mu.Lock()
        if _, exists := pm.rules[localAddr]; exists {
                pm.mu.Unlock()
                return nil, fmt.Errorf("规则已存在: %s", localAddr)
        }
        listener, err := net.Listen("tcp", localAddr)
        if err != nil {
                pm.mu.Unlock()
                return nil, fmt.Errorf("无法监听 %s: %v", localAddr, err)
        }

        rule := &ForwardRule{
                Name:        name,
                LocalAddr:   localAddr,
                RemoteAddr:  remoteAddr,
                listener:    listener,
                activeConns: make(map[net.Conn]struct{}),
        }
        pm.rules[localAddr] = rule
        go pm.startListenerLoop(rule)
        pm.mu.Unlock() // Unlock BEFORE saving

        if err := pm.saveRules(); err != nil {
                // 日志已删除: log.Printf("警告: 添加规则后持久化失败: %v", err)
        }
        // 日志已删除: log.Printf("规则已添加: %s (%s -> %s)", name, localAddr, remoteAddr)
        return rule, nil
}

func (pm *ProxyManager) UpdateRule(originalLocalAddr, newName, newLocalAddr, newRemoteAddr string) error {
        if !strings.Contains(newLocalAddr, ":") {
                newLocalAddr = "0.0.0.0:" + newLocalAddr
        }

        pm.mu.RLock()
        rule, exists := pm.rules[originalLocalAddr]
        if !exists {
                pm.mu.RUnlock()
                return fmt.Errorf("规则不存在: %s", originalLocalAddr)
        }
        originalRemoteAddr := rule.RemoteAddr
        pm.mu.RUnlock()

        if originalLocalAddr == newLocalAddr && originalRemoteAddr == newRemoteAddr {
                pm.mu.Lock()
                rule, exists := pm.rules[originalLocalAddr]
                if !exists {
                        pm.mu.Unlock()
                        return fmt.Errorf("规则 %s 在更新期间被删除", originalLocalAddr)
                }
                rule.Name = newName
                pm.mu.Unlock()

                // 日志已删除: log.Printf("规则 '%s' (%s) 名称已更新为 '%s'，现有连接不受影响。", originalLocalAddr, originalName, newName)
                return pm.saveRules()
        }

        // 日志已删除: log.Printf("规则 '%s' 的地址已更改 (新本地: %s, 新远程: %s)，将重启规则并断开现有连接。", originalLocalAddr, newLocalAddr, newRemoteAddr)

        if err := pm.DeleteRule(originalLocalAddr); err != nil {
                return fmt.Errorf("更新失败：无法删除旧规则 %s: %w", originalLocalAddr, err)
        }

        if _, err := pm.AddRule(newName, newLocalAddr, newRemoteAddr); err != nil {
                return fmt.Errorf("更新失败：已成功删除旧规则，但无法添加新规则 %s: %w", newLocalAddr, err)
        }

        return nil
}

func (pm *ProxyManager) DeleteRule(localAddr string) error {
        pm.mu.Lock()
        rule, exists := pm.rules[localAddr]
        if !exists {
                pm.mu.Unlock()
                return fmt.Errorf("规则不存在: %s", localAddr)
        }

        _ = rule.listener.Close()

        rule.connsMu.Lock()
        for conn := range rule.activeConns {
                conn.Close()
        }
        rule.connsMu.Unlock()

        delete(pm.rules, localAddr)
        pm.mu.Unlock() // Unlock BEFORE saving

        if err := pm.saveRules(); err != nil {
                // 日志已删除: log.Printf("警告: 删除规则后持久化失败: %v", err)
        }
        // 日志已删除: log.Printf("规则已删除: %s (%s -> %s)。已关闭 %d 个活动连接。", rule.Name, rule.LocalAddr, rule.RemoteAddr, activeCount)
        return nil
}

func (pm *ProxyManager) GetRules() []*ForwardRule {
        pm.mu.RLock()
        defer pm.mu.RUnlock()
        rules := make([]*ForwardRule, 0, len(pm.rules))
        for _, rule := range pm.rules {
                rules = append(rules, &ForwardRule{
                        Name:       rule.Name,
                        LocalAddr:  rule.LocalAddr,
                        RemoteAddr: rule.RemoteAddr,
                })
        }
        return rules
}

func (pm *ProxyManager) apiRulesHandler(w http.ResponseWriter, r *http.Request) {
        switch r.Method {
        case http.MethodGet:
                w.Header().Set("Content-Type", "application/json")
                _ = json.NewEncoder(w).Encode(pm.GetRules())
        case http.MethodPost:
                var rule ForwardRule
                if err := json.NewDecoder(r.Body).Decode(&rule); err != nil {
                        http.Error(w, err.Error(), http.StatusBadRequest)
                        return
                }
                if _, err := pm.AddRule(rule.Name, rule.LocalAddr, rule.RemoteAddr); err != nil {
                        http.Error(w, err.Error(), http.StatusConflict)
                        return
                }
                w.WriteHeader(http.StatusCreated)
        case http.MethodPut:
                var req UpdateRuleRequest
                if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
                        http.Error(w, "无效的请求体: "+err.Error(), http.StatusBadRequest)
                        return
                }
                if req.OriginalLocalAddr == "" {
                        http.Error(w, "缺少 'original_local_addr' 字段", http.StatusBadRequest)
                        return
                }
                if err := pm.UpdateRule(req.OriginalLocalAddr, req.Name, req.LocalAddr, req.RemoteAddr); err != nil {
                        http.Error(w, err.Error(), http.StatusInternalServerError)
                        return
                }
                w.WriteHeader(http.StatusOK)
        case http.MethodDelete:
                var rule ForwardRule
                if err := json.NewDecoder(r.Body).Decode(&rule); err != nil {
                        http.Error(w, err.Error(), http.StatusBadRequest)
                        return
                }
                if err := pm.DeleteRule(rule.LocalAddr); err != nil {
                        http.Error(w, err.Error(), http.StatusNotFound)
                        return
                }
                w.WriteHeader(http.StatusOK)
        default:
                http.Error(w, "方法不允许", http.StatusMethodNotAllowed)
        }
}

// --- Connection Handling ---
func (pm *ProxyManager) startListenerLoop(rule *ForwardRule) {
        for {
                clientConn, err := rule.listener.Accept()
                if err != nil {
                        if strings.Contains(err.Error(), "use of closed network connection") {
                                return
                        }
                        // 日志已删除: log.Printf("监听 %s 时发生错误: %v", rule.LocalAddr, err)
                        continue
                }

                rule.connsMu.Lock()
                rule.activeConns[clientConn] = struct{}{}
                rule.connsMu.Unlock()

                go pm.handleConnection(clientConn, rule)
        }
}

func (pm *ProxyManager) handleConnection(clientConn net.Conn, rule *ForwardRule) {
        defer func() {
                rule.connsMu.Lock()
                delete(rule.activeConns, clientConn)
                rule.connsMu.Unlock()
                clientConn.Close()
        }()

        pm.mu.RLock()
        remoteAddr := rule.RemoteAddr
        pm.mu.RUnlock()

        remoteConn, err := net.DialTimeout("tcp", remoteAddr, 10*time.Second)
        if err != nil {
                // 日志已删除: log.Printf("无法连接到远程地址 %s: %v", remoteAddr, err)
                return
        }
        defer remoteConn.Close()

        var wg sync.WaitGroup
        wg.Add(2)

        go func() {
                defer wg.Done()
                _, _ = io.Copy(clientConn, remoteConn)
                if tcpConn, ok := clientConn.(*net.TCPConn); ok {
                        _ = tcpConn.CloseWrite()
                }
        }()

        go func() {
                defer wg.Done()
                _, _ = io.Copy(remoteConn, clientConn)
                if tcpConn, ok := remoteConn.(*net.TCPConn); ok {
                        _ = tcpConn.CloseWrite()
                }
        }()

        wg.Wait()
}
