#!/bin/bash

#
# PortProxy 一键安装与管理脚本
# 作者: Kirito (由 AI 助手美化和增强)
#

# --- 配置 ---
RELEASE_URL="https://github.com/kirito201711/PortProxy/releases/download/v1.0/portProxy.tar.gz"
INSTALL_DIR="/opt/portProxy"
BIN_LINK="/usr/local/bin/portProxy"
SERVICE_NAME="portProxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="/etc/default/${SERVICE_NAME}"

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color
DIM='\033[2m' # Dim color for disabled options

# --- 状态变量 ---
IS_INSTALLED=false
IS_ACTIVE=false
INSTALL_STATUS=""
PROXY_URL=""

# --- 辅助函数 ---
info() { echo -e "${GREEN}✔${NC} $1"; }
warn() { echo -e "${YELLOW}➜${NC} $1"; }
error() { echo -e "${RED}✖${NC} $1"; exit 1; }
error_msg() { echo -e "${RED}✖${NC} $1"; }
prompt() { read -p "$(echo -e "${CYAN}==>${NC} $1")" "$2" < /dev/tty; }

# 显示加载动画的函数
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b"
    done
    printf " \b\b\b\b"
}

# 带加载动画执行命令
execute_with_spinner() {
    local msg="$1"
    shift
    echo -n -e "${BLUE}  ... ${NC}${msg}"
    "$@" &> /dev/null &
    spinner $!
    # 检查命令的退出状态
    if wait $! ; then
        echo -e "\r${GREEN}  ✔  ${NC}${msg} ${GREEN}完成${NC}"
    else
        echo -e "\r${RED}  ✖  ${NC}${msg} ${RED}失败${NC}"
        error "操作失败，请检查输出日志。"
    fi
}


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

# 检查 PortProxy 的安装状态和服务状态
check_status() {
    if [ -f "$SERVICE_FILE" ] && [ -d "$INSTALL_DIR" ]; then
        IS_INSTALLED=true
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            IS_ACTIVE=true
            INSTALL_STATUS="${GREEN}✅ 已安装 (运行中)${NC}"
        else
            IS_ACTIVE=false
            INSTALL_STATUS="${YELLOW}✅ 已安装 (已停止)${NC}"
        fi
    else
        IS_INSTALLED=false
        IS_ACTIVE=false
        INSTALL_STATUS="${RED}❌ 未安装${NC}"
    fi
}

# --- 功能函数 ---

# 交互式获取代理配置
prompt_for_proxy() {
    PROXY_URL="" # 每次调用时重置
    prompt "是否为 GitHub Release 使用下载代理? (解决国内访问慢问题) [Y/n]: " use_proxy
    if [[ ! "$use_proxy" =~ ^[nN]$ ]]; then
        local default_proxy="https://gh-proxy.com/"
        prompt "请输入代理地址 [默认: ${default_proxy}]: " custom_proxy
        PROXY_URL=${custom_proxy:-${default_proxy}}
        # 确保代理地址以 / 结尾
        if [[ "${PROXY_URL: -1}" != "/" ]]; then
            PROXY_URL="${PROXY_URL}/"
        fi
        info "已启用下载代理: ${CYAN}${PROXY_URL}${NC}"
    else
        info "将不使用下载代理，直接从 GitHub 下载。"
    fi
}

# 下载并解压
download_and_extract() {
    local url_to_download="$1"
    info "准备从以下地址下载 PortProxy:"
    echo -e "${CYAN}${url_to_download}${NC}"
    
    TMP_DIR=$(mktemp -d)
    # 设置 trap 以确保临时目录在脚本退出时被删除
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo
    if command -v curl &> /dev/null; then
        info "使用 curl 下载 (带进度条)..."
        curl -L --progress-bar -o "$TMP_DIR/portProxy.tar.gz" "$url_to_download" || error "使用 curl 下载失败。"
    elif command -v wget &> /dev/null; then
        info "使用 wget 下载 (带进度条)..."
        wget -q --show-progress -O "$TMP_DIR/portProxy.tar.gz" "$url_to_download" || error "使用 wget 下载失败。"
    else
        error "未找到 curl 或 wget。请先安装其中一个。"
    fi
    echo
    info "下载完成，正在解压..."
    tar -xzf "$TMP_DIR/portProxy.tar.gz" -C "$TMP_DIR" || error "解压失败。"
    EXTRACTED_PATH="$TMP_DIR"
}

# 安装文件
install_files() {
    info "正在安装文件到 ${INSTALL_DIR}..."
    mkdir -p "$INSTALL_DIR" || error "创建安装目录失败。"
    cp "${EXTRACTED_PATH}/portProxy" "${EXTRACTED_PATH}/index.html" "${EXTRACTED_PATH}/login.html" "$INSTALL_DIR/" || error "复制文件失败。"
    chmod +x "${INSTALL_DIR}/portProxy" || error "设置执行权限失败。"
    info "创建软链接到 ${BIN_LINK}..."
    ln -sf "${INSTALL_DIR}/portProxy" "$BIN_LINK" || error "创建软链接失败。"
}

# 交互式获取用户配置
prompt_for_config() {
    info "开始进行交互式配置..."
    while true; do
        prompt "请输入 Web 管理面板的监听端口 [默认: 9090]: " user_admin_port
        user_admin_port=${user_admin_port:-9090}
        if [[ "$user_admin_port" =~ ^[0-9]+$ ]] && [ "$user_admin_port" -ge 1 ] && [ "$user_admin_port" -le 65535 ]; then break
        else error_msg "端口无效。请输入一个 1-65535 之间的数字。"; fi
    done
    while true; do
        read -s -p "$(echo -e "${CYAN}==>${NC} 请输入 Web 管理面板的密码 (输入时不可见): ")" user_admin_password < /dev/tty; echo
        if [ -z "$user_admin_password" ]; then error_msg "密码不能为空，请重新输入。"; continue; fi
        read -s -p "$(echo -e "${CYAN}==>${NC} 请再次输入密码以确认: ")" user_admin_password_confirm < /dev/tty; echo
        if [ "$user_admin_password" == "$user_admin_password_confirm" ]; then break
        else error_msg "两次输入的密码不匹配，请重试。"; fi
    done
    info "配置信息已收集完毕。"
}

# 创建 systemd 服务
create_systemd_service() {
    info "正在创建 systemd 服务..."
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=PortProxy - A dynamic TCP forwarder
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${INSTALL_DIR}/portProxy \$PORTPROXY_OPTS
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    info "正在创建配置文件 ${ENV_FILE}..."
    cat > "$ENV_FILE" << EOF
# PortProxy 启动选项
# 此文件由 install.sh 自动生成
PORTPROXY_OPTS="-admin=:${user_admin_port} -password='${user_admin_password}'"
EOF

    execute_with_spinner "重新加载 systemd 配置" systemctl daemon-reload
}

# 安装后显示总结信息
post_install_summary() {
    local ip_address
    ip_address=$(hostname -I | awk '{print $1}')
    [ -z "$ip_address" ] && ip_address="127.0.0.1" # Fallback
    echo -e "${PURPLE}-----------------------------------------------------${NC}"
    echo -e "${YELLOW}🎉 PortProxy 安装成功! 🎉${NC}"
    echo
    echo -e "  Web 管理面板地址: ${GREEN}http://${ip_address}:${user_admin_port}${NC}"
    echo -e "  Web 管理面板密码: ${YELLOW}******** (您设置的密码)${NC}"
    echo
    echo -e "  配置文件路径: ${CYAN}${ENV_FILE}${NC}"
    echo -e "  安装目录:     ${CYAN}${INSTALL_DIR}${NC}"
    echo
    echo -e "  你可以使用 ${GREEN}'systemctl <start|stop|status> ${SERVICE_NAME}'${NC} 来管理服务,"
    echo -e "  或通过本脚本的 ${PURPLE}'管理服务'${NC} 菜单进行操作。"
    echo -e "${PURPLE}-----------------------------------------------------${NC}"
}

# 安装主流程
do_install() {
    echo -e "\n--- ${YELLOW}开始安装 PortProxy${NC} ---"
    if $IS_INSTALLED; then
        warn "检测到旧的安装。"
        prompt "是否覆盖安装？所有配置将被重置。 [y/N]: " confirm_overwrite
        if [[ ! "$confirm_overwrite" =~ ^[yY]([eE][sS])?$ ]]; then
            info "操作已取消。"
            return
        fi
        do_uninstall "silent" # 先以静默模式卸载
    fi

    prompt_for_proxy
    local FINAL_RELEASE_URL="${PROXY_URL}${RELEASE_URL}"

    download_and_extract "$FINAL_RELEASE_URL"
    install_files
    prompt_for_config
    create_systemd_service
    echo
    
    prompt "是否立即启动并设置开机自启? [Y/n]: " start_now
    if [[ ! "$start_now" =~ ^[nN]$ ]]; then
        execute_with_spinner "启动并设置开机自启" systemctl enable --now "$SERVICE_NAME"
    fi

    echo
    post_install_summary
    echo
}

# 卸载主流程
do_uninstall() {
    local silent_mode=$1
    if [ "$silent_mode" != "silent" ]; then
        echo -e "\n--- ${RED}开始卸载 PortProxy${NC} ---"
        if ! $IS_INSTALLED; then
            warn "PortProxy 未安装，无需卸载。"
            return
        fi
        prompt "确定要卸载 PortProxy 吗？所有配置文件和规则都将被删除。 [y/N]: " confirm_uninstall
        if [[ ! "$confirm_uninstall" =~ ^[yY]([eE][sS])?$ ]]; then
            info "操作已取消。"
            return
        fi
    fi

    execute_with_spinner "停止并禁用 ${SERVICE_NAME} 服务" systemctl disable --now "$SERVICE_NAME"
    
    info "正在删除文件..."
    rm -f "$SERVICE_FILE"
    rm -f "$ENV_FILE"
    rm -f "$BIN_LINK"
    rm -rf "$INSTALL_DIR"
    
    execute_with_spinner "重新加载 systemd 配置" systemctl daemon-reload

    if [ "$silent_mode" != "silent" ]; then
        info "PortProxy 已成功卸载。"
    fi
}

# 服务管理菜单
manage_service_menu() {
    while true; do
        check_status
        clear
        echo -e "${PURPLE}--- PortProxy 服务管理 ---${NC}"
        echo
        printf "  %-15s %s\n" "当前状态:" "$INSTALL_STATUS"
        echo
        echo -e "  ${GREEN}1.${NC} 启动服务"
        echo -e "  ${GREEN}2.${NC} 停止服务"
        echo -e "  ${GREEN}3.${NC} 重启服务"
        echo -e "  ${YELLOW}4.${NC} 查看服务状态"
        echo -e "  ${YELLOW}5.${NC} 查看服务日志"
        echo -e "  -------------------------"
        echo -e "  ${CYAN}0.${NC} 返回主菜单"
        echo
        prompt "请输入选项 [0-5]: " choice

        case $choice in
            1) execute_with_spinner "启动服务" systemctl start "$SERVICE_NAME"; press_any_key ;;
            2) execute_with_spinner "停止服务" systemctl stop "$SERVICE_NAME"; press_any_key ;;
            3) execute_with_spinner "重启服务" systemctl restart "$SERVICE_NAME"; press_any_key ;;
            4) clear; systemctl --no-pager status "$SERVICE_NAME"; press_any_key ;;
            5) clear; journalctl -u "$SERVICE_NAME" -f -n 50 --no-pager; press_any_key ;;
            0) break ;;
            *) error_msg "无效的选项，请重新输入。"; sleep 1.5 ;;
        esac
    done
}


# 等待用户按键
press_any_key() {
    echo
    prompt "按任意键返回..." "key"
}

# 显示主菜单
show_menu() {
    check_status
    
    clear
    echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                     ║${NC}"
    echo -e "${CYAN}║           ${YELLOW}PortProxy 一键安装管理脚本${CYAN}           ║${NC}"
    echo -e "${CYAN}║           ${DIM}v2.1 Proxy Enhanced by AI${CYAN}         ║${NC}"
    echo -e "${CYAN}║                                                     ║${NC}"
    echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${NC}"
    echo
    printf "  %-15s %s\n" "当前状态:" "$INSTALL_STATUS"
    echo

    if $IS_INSTALLED; then
        echo -e "  ${GREEN}1.${NC} 重新安装 PortProxy"
        echo -e "  ${GREEN}2.${NC} 卸载 PortProxy"
        echo -e "  ${PURPLE}3.${NC} 管理服务"
    else
        echo -e "  ${GREEN}1.${NC} 安装 PortProxy"
        echo -e "  ${DIM}2. 卸载 PortProxy (未安装)${NC}"
        echo -e "  ${DIM}3. 管理服务 (未安装)${NC}"
    fi
    echo -e "  ---------------------------------------------------"
    echo -e "  ${CYAN}0.${NC} 退出脚本"
    echo
    prompt "请输入选项 [0-3]: " choice
}

# 主函数
main() {
    # 捕获中断信号，确保临时目录被清理
    trap 'rm -rf "$TMP_DIR" &> /dev/null; echo -e "\n操作被中断。"; exit 1' INT TERM

    check_root
    check_systemd

    # 支持命令行参数直接执行安装或卸载
    if [[ "$1" == "install" ]]; then
        check_status; do_install; exit 0
    elif [[ "$1" == "uninstall" ]]; then
        check_status; do_uninstall; exit 0
    fi
    
    while true; do
        show_menu
        case $choice in
            1) do_install; press_any_key ;;
            2) 
                if $IS_INSTALLED; then
                    do_uninstall; press_any_key
                else
                    error_msg "PortProxy 未安装，无法执行卸载操作。"
                    sleep 1.5
                fi
                ;;
            3)
                if $IS_INSTALLED; then
                    manage_service_menu
                else
                    error_msg "PortProxy 未安装，无法管理服务。"
                    sleep 1.5
                fi
                ;;
            0) echo "感谢使用，退出脚本。"; exit 0 ;;
            *) error_msg "无效的选项，请重新输入。"; sleep 1.5 ;;
        esac
    done
}

# 脚本入口
main "$@"
