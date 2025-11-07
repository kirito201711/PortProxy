#!/bin/bash

# PortProxy 一键安装管理脚本 (终极美化 & 增强版)
#
# 特性:
# 1. 精美、动态的菜单界面，实时显示安装与服务状态.
# 2. 下载时显示优雅的 spinner 加载动画.
# 3. 安装后自动启动并设置开机自启，无需确认.
# 4. 增加服务管理功能：重启、停止、查看日志 (安装后可用).
# 5. 交互流程优化，提供清晰的步骤指引和操作反馈.

# --- 配置 ---
RELEASE_URL="https://github.com/kirito201711/PortProxy/releases/download/v1.0/portProxy.tar.gz"
INSTALL_DIR="/opt/portProxy"
BIN_LINK="/usr/local/bin/portProxy"
SERVICE_NAME="portProxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="/etc/default/${SERVICE_NAME}"

# --- 颜色与样式 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# --- 状态变量 ---
IS_INSTALLED=false
IS_ACTIVE=false

# --- 辅助函数 ---
info() { echo -e "${GREEN}${BOLD}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}${BOLD}[WARN]${NC} $1"; }
error() { echo -e "${RED}${BOLD}[ERROR]${NC} $1"; exit 1; }
error_msg() { echo -e "${RED}${BOLD}[ERROR]${NC} $1"; }
step() { echo -e "\n${CYAN}==> $1${NC}"; }

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "此脚本必须以 root 权限运行。请使用 'sudo ./install.sh'。"
    fi
}

# 检查系统是否使用 systemd
check_systemd() {
    if ! [ -d /run/systemd/system ]; then
        error "未检测到 systemd，此脚本无法创建服务。请检查你的操作系统。"
    fi
}

# 检查安装与服务状态
check_status() {
    if [ -f "$SERVICE_FILE" ] && [ -d "$INSTALL_DIR" ]; then
        IS_INSTALLED=true
        INSTALL_STATUS="${GREEN}已安装${NC}"
        # 检查服务是否正在运行
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            IS_ACTIVE=true
            SERVICE_STATUS="${GREEN}运行中 (active)${NC}"
        else
            IS_ACTIVE=false
            SERVICE_STATUS="${RED}未运行 (inactive)${NC}"
        fi
    else
        IS_INSTALLED=false
        IS_ACTIVE=false
        INSTALL_STATUS="${RED}未安装${NC}"
        SERVICE_STATUS="${DIM}N/A${NC}"
    fi
}

# 等待用户按回车键继续
press_enter_to_continue() {
    echo -e "\n${YELLOW}请按 Enter 键返回主菜单...${NC}"
    read -r
}

# Spinner 动画
spinner() {
    local pid=$1
    local spin='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${CYAN}${spin:$i:1}${NC} 正在执行..."
        sleep 0.1
    done
    printf "\r${GREEN}✔${NC} 操作完成.    \n"
}

# --- 功能函数 ---

# 下载并解压 (带 Spinner)
download_and_extract() {
    step "1. 下载 PortProxy 组件"
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    if command -v curl &> /dev/null; then
        (curl -sL "$RELEASE_URL" -o "$TMP_DIR/portProxy.tar.gz") &
    elif command -v wget &> /dev/null; then
        (wget -qO "$TMP_DIR/portProxy.tar.gz" "$RELEASE_URL") &
    else
        error "未找到 curl 或 wget。请先安装其中一个。"
    fi
    
    spinner $!
    if ! wait $!; then error "下载失败，请检查网络或 URL: $RELEASE_URL"; fi

    step "2. 解压文件"
    tar -xzf "$TMP_DIR/portProxy.tar.gz" -C "$TMP_DIR" || error "解压失败。"
    EXTRACTED_PATH="$TMP_DIR"
}

# 安装文件
install_files() {
    step "3. 安装文件"
    mkdir -p "$INSTALL_DIR" || error "创建安装目录失败。"
    info "  - 目标目录: ${INSTALL_DIR}"
    cp "${EXTRACTED_PATH}/portProxy" "${EXTRACTED_PATH}/index.html" "${EXTRACTED_PATH}/login.html" "$INSTALL_DIR/" || error "复制文件失败。"
    chmod +x "${INSTALL_DIR}/portProxy" || error "设置执行权限失败。"
    info "  - 创建软链接: ${BIN_LINK}"
    ln -sf "${INSTALL_DIR}/portProxy" "$BIN_LINK" || error "创建软链接失败。"
}

# 交互式获取用户配置
prompt_for_config() {
    step "4. 配置管理面板"
    while true; do
        read -p "$(echo -e "${YELLOW}请输入 Web 管理面板监听端口 [默认: 9090]: ${NC}")" user_admin_port < /dev/tty
        user_admin_port=${user_admin_port:-9090}
        if [[ "$user_admin_port" =~ ^[0-9]+$ ]] && [ "$user_admin_port" -ge 1 ] && [ "$user_admin_port" -le 65535 ]; then break
        else error_msg "端口无效。请输入一个 1-65535 之间的数字。"; fi
    done
    while true; do
        read -s -p "$(echo -e "${YELLOW}请输入 Web 管理面板密码 (输入时不可见): ${NC}")" user_admin_password < /dev/tty; echo
        if [ -z "$user_admin_password" ]; then error_msg "密码不能为空，请重新输入。"; continue; fi
        read -s -p "$(echo -e "${YELLOW}请再次输入密码以确认: ${NC}")" user_admin_password_confirm < /dev/tty; echo
        if [ "$user_admin_password" == "$user_admin_password_confirm" ]; then break
        else error_msg "两次输入的密码不匹配，请重试。"; fi
    done
}

# 创建 systemd 服务
create_systemd_service() {
    step "5. 创建 systemd 服务"
    info "  - 服务文件: ${SERVICE_FILE}"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Dynamic Zero-Copy TCP Forwarder
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${INSTALL_DIR}/portProxy \$PORTPROXY_OPTS
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    info "  - 配置文件: ${ENV_FILE}"
    cat > "$ENV_FILE" << EOF
# PortProxy 启动选项
# 此文件由 install.sh 自动生成
PORTPROXY_OPTS="-admin=:${user_admin_port} -password='${user_admin_password}'"
EOF

    systemctl daemon-reload
    info "systemd 配置已重载。"
}

# 安装主流程
do_install() {
    if $IS_INSTALLED; then
        warn "检测到 PortProxy 已安装。"
        read -p "是否覆盖安装？现有配置将丢失。 [y/N]: " confirm_overwrite < /dev/tty
        if [[ ! "$confirm_overwrite" =~ ^[yY]([eE][sS])?$ ]]; then
            info "操作已取消。"
            return
        fi
        do_uninstall "silent" # 先以静默模式卸载
    fi

    clear
    echo -e "${BLUE}--- 开始安装 PortProxy ---${NC}"
    download_and_extract
    install_files
    prompt_for_config
    create_systemd_service

    step "6. 启动并设置开机自启"
    systemctl enable "$SERVICE_NAME" >/dev/null
    systemctl start "$SERVICE_NAME"
    info "${SERVICE_NAME} 服务已启动并设置为开机自启。"

    echo -e "\n${GREEN}${BOLD}🎉 PortProxy 安装成功！ 🎉${NC}"
    echo "--------------------------------------------------"
    echo -e "  Web 管理面板: ${YELLOW}http://<你的服务器IP>:${user_admin_port}${NC}"
    echo -e "  默认配置文件: ${ENV_FILE}"
    echo "--------------------------------------------------"
    press_enter_to_continue
}

# 卸载主流程
do_uninstall() {
    local silent_mode=$1
    if [ "$silent_mode" != "silent" ]; then
        if ! $IS_INSTALLED; then
            warn "PortProxy 未安装，无需卸载。"
            press_enter_to_continue
            return
        fi
        read -p "确定要卸载 PortProxy 吗？所有配置文件和规则都将被删除。 [y/N]: " confirm_uninstall < /dev/tty
        if [[ ! "$confirm_uninstall" =~ ^[yY]([eE][sS])?$ ]]; then
            info "操作已取消。"
            return
        fi
    fi

    step "正在停止并禁用 ${SERVICE_NAME} 服务..."
    (systemctl stop "$SERVICE_NAME" &>/dev/null; systemctl disable "$SERVICE_NAME" &>/dev/null) &
    spinner $!

    step "正在删除相关文件..."
    rm -f "$SERVICE_FILE"
    rm -f "$ENV_FILE"
    rm -f "$BIN_LINK"
    rm -rf "$INSTALL_DIR"
    info "文件已清理。"
    
    step "正在重载 systemd 配置..."
    systemctl daemon-reload &
    spinner $!

    if [ "$silent_mode" != "silent" ]; then
        info "PortProxy 已成功卸载。"
        press_enter_to_continue
    fi
}

# 服务管理功能
do_restart() {
    step "正在重启 ${SERVICE_NAME} 服务..."
    systemctl restart "$SERVICE_NAME" &
    spinner $!
    info "${SERVICE_NAME} 服务已重启。"
    press_enter_to_continue
}

do_stop() {
    step "正在停止 ${SERVICE_NAME} 服务..."
    systemctl stop "$SERVICE_NAME" &
    spinner $!
    info "${SERVICE_NAME} 服务已停止。"
    press_enter_to_continue
}

view_logs() {
    step "正在显示 ${SERVICE_NAME} 的实时日志 (最近 100 条)..."
    echo -e "${DIM}按 Ctrl+C 退出日志查看。${NC}"
    sleep 1
    journalctl -u "$SERVICE_NAME" -f -n 100
    press_enter_to_continue
}

# --- 脚本主入口 ---

show_menu() {
    check_status
    clear
    echo -e "${CYAN}┌───────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│                                                   │${NC}"
    echo -e "${CYAN}│          ${BOLD}${YELLOW}PortProxy 一键安装管理脚本${NC}${CYAN}           │${NC}"
    echo -e "${CYAN}│                                                   │${NC}"
    echo -e "${CYAN}└───────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "  ${BLUE}当前状态:${NC}"
    printf "  %-20s %s\n" "  - 安装状态:" "$INSTALL_STATUS"
    printf "  %-20s %s\n" "  - 服务状态:" "$SERVICE_STATUS"
    echo
    echo -e "${BLUE}主菜单:${NC}"
    if $IS_INSTALLED; then
        echo -e "  ${GREEN}1.${NC} 重新安装 PortProxy"
        echo -e "  ${GREEN}2.${NC} 卸载 PortProxy"
        echo -e "  -------------------------------------------------"
        echo -e "  ${GREEN}3.${NC} 重启 PortProxy 服务"
        echo -e "  ${GREEN}4.${NC} 停止 PortProxy 服务"
        echo -e "  ${GREEN}5.${NC} 查看 PortProxy 日志"
    else
        echo -e "  ${GREEN}1.${NC} 安装 PortProxy"
        echo -e "  ${DIM}2. 卸载 PortProxy (未安装)${NC}"
        echo -e "  -------------------------------------------------"
        echo -e "  ${DIM}3. 重启服务 (未安装)${NC}"
        echo -e "  ${DIM}4. 停止服务 (未安装)${NC}"
        echo -e "  ${DIM}5. 查看日志 (未安装)${NC}"
    fi
    echo -e "  -------------------------------------------------"
    echo -e "  ${GREEN}0.${NC} 退出脚本"
    echo
}

main() {
    check_root
    check_systemd

    # 支持命令行参数
    if [[ "$1" == "install" ]]; then
        check_status; do_install; exit 0
    elif [[ "$1" == "uninstall" ]]; then
        check_status; do_uninstall; exit 0
    fi
    
    while true; do
        show_menu
        read -p "$(echo -e "${CYAN}❯${NC} 请选择操作: ")" choice < /dev/tty
        case $choice in
            1) do_install ;;
            2) do_uninstall ;;
            3) if $IS_INSTALLED; then do_restart; else error_msg "PortProxy 未安装，无法执行此操作。"; sleep 1.5; fi ;;
            4) if $IS_INSTALLED; then do_stop; else error_msg "PortProxy 未安装，无法执行此操作。"; sleep 1.5; fi ;;
            5) if $IS_INSTALLED; then view_logs; else error_msg "PortProxy 未安装，无法执行此操作。"; sleep 1.5; fi ;;
            0) echo "退出脚本。"; exit 0 ;;
            *) error_msg "无效的选项，请重新输入。"; sleep 1.5 ;;
        esac
    done
}

main "$@"
