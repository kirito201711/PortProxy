#!/bin/bash

# PortProxy 安装脚本 (美化菜单 & 进度条版本)
# 功能:
# 1. 提供美观且动态的菜单选项：安装、卸载、退出.
# 2. 下载时显示进度条.
# 3. 交互式提示用户输入端口和密码 (安装时).
# 4. 将文件安装到指定目录并创建 systemd 服务.
# 5. 提供完整的卸载功能，并在安装后提示启动服务.
# 6. 自动检测安装状态并在菜单中显示.

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
NC='\033[0m' # No Color
DIM='\033[2m' # Dim color for disabled options

# --- 状态变量 ---
IS_INSTALLED=false

# --- 辅助函数 ---
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
error_msg() { echo -e "${RED}[ERROR]${NC} $1"; }

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

# 检查 PortProxy 的安装状态
check_status() {
    if [ -f "$SERVICE_FILE" ] && [ -d "$INSTALL_DIR" ]; then
        IS_INSTALLED=true
        INSTALL_STATUS="${GREEN}已安装${NC}"
    else
        IS_INSTALLED=false
        INSTALL_STATUS="${RED}未安装${NC}"
    fi
}


# --- 功能函数 ---

# 下载并解压
download_and_extract() {
    info "正在准备下载 PortProxy..."
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo # Add a newline for better formatting before the progress bar
    if command -v curl &> /dev/null; then
        info "使用 curl 下载 (带进度条)..."
        # 移除 -s (silent), -L 用于跟随重定向
        curl -L -o "$TMP_DIR/portProxy.tar.gz" "$RELEASE_URL" || error "使用 curl 下载失败。"
    elif command -v wget &> /dev/null; then
        info "使用 wget 下载 (带进度条)..."
        # 移除 -q (quiet)
        wget -O "$TMP_DIR/portProxy.tar.gz" "$RELEASE_URL" || error "使用 wget 下载失败。"
    else
        error "未找到 curl 或 wget。请先安装其中一个。"
    fi
    echo # Add a newline after the progress bar
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
        read -p "请输入 Web 管理面板的监听端口 [默认: 9090]: " user_admin_port < /dev/tty
        user_admin_port=${user_admin_port:-9090}
        if [[ "$user_admin_port" =~ ^[0-9]+$ ]] && [ "$user_admin_port" -ge 1 ] && [ "$user_admin_port" -le 65535 ]; then break
        else error_msg "端口无效。请输入一个 1-65535 之间的数字。"; fi
    done
    while true; do
        read -s -p "请输入 Web 管理面板的密码 (输入时不可见): " user_admin_password < /dev/tty; echo
        if [ -z "$user_admin_password" ]; then error_msg "密码不能为空，请重新输入。"; continue; fi
        read -s -p "请再次输入密码以确认: " user_admin_password_confirm < /dev/tty; echo
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

    info "正在创建配置文件 ${ENV_FILE}..."
    cat > "$ENV_FILE" << EOF
# PortProxy 启动选项
# 此文件由 install.sh 自动生成
PORTPROXY_OPTS="-admin=:${user_admin_port} -password='${user_admin_password}'"
EOF

    info "重新加载 systemd 配置..."
    systemctl daemon-reload
}

# 安装主流程
do_install() {
    info "--- 开始安装 PortProxy ---"
    if $IS_INSTALLED; then
        warn "检测到旧的安装。"
        read -p "是否覆盖安装？ [y/N]: " confirm_overwrite < /dev/tty
        if [[ ! "$confirm_overwrite" =~ ^[yY]([eE][sS])?$ ]]; then
            info "操作已取消。"
            return
        fi
        do_uninstall "silent" # 先以静默模式卸载
    fi

    download_and_extract
    install_files
    prompt_for_config
    create_systemd_service
    echo
    info "PortProxy 安装成功！"
    info "配置已根据你的输入自动生成并保存在: ${ENV_FILE}"
    echo
    
    read -p "是否立即启动并设置开机自启? [Y/n]: " start_now < /dev/tty
    if [[ ! "$start_now" =~ ^[nN]$ ]]; then
        info "正在启动并设置开机自启..."
        systemctl start "$SERVICE_NAME"
        systemctl enable "$SERVICE_NAME"
        info "${SERVICE_NAME} 服务已启动。"
    fi

    echo
    info "你可以使用以下命令管理服务:"
    echo -e "  启动服务:   ${GREEN}sudo systemctl start ${SERVICE_NAME}${NC}"
    echo -e "  停止服务:   ${GREEN}sudo systemctl stop ${SERVICE_NAME}${NC}"
    echo -e "  设置开机自启: ${GREEN}sudo systemctl enable ${SERVICE_NAME}${NC}"
    echo -e "  取消开机自启: ${GREEN}sudo systemctl disable ${SERVICE_NAME}${NC}"
    echo -e "  查看状态:   ${GREEN}sudo systemctl status ${SERVICE_NAME}${NC}"
    echo
}

# 卸载主流程
do_uninstall() {
    local silent_mode=$1
    if [ "$silent_mode" != "silent" ]; then
        info "--- 开始卸载 PortProxy ---"
        if ! $IS_INSTALLED; then
            warn "PortProxy 未安装，无需卸载。"
            return
        fi
        read -p "确定要卸载 PortProxy 吗？所有配置文件和规则都将被删除。 [y/N]: " confirm_uninstall < /dev/tty
        if [[ ! "$confirm_uninstall" =~ ^[yY]([eE][sS])?$ ]]; then
            info "操作已取消。"
            return
        fi
    fi

    info "正在停止和禁用 ${SERVICE_NAME} 服务..."
    systemctl stop "$SERVICE_NAME" &>/dev/null
    systemctl disable "$SERVICE_NAME" &>/dev/null
    
    info "正在删除文件..."
    rm -f "$SERVICE_FILE"
    rm -f "$ENV_FILE"
    rm -f "$BIN_LINK"
    rm -rf "$INSTALL_DIR"
    
    info "重新加载 systemd 配置..."
    systemctl daemon-reload

    if [ "$silent_mode" != "silent" ]; then
        info "PortProxy 已成功卸载。"
    fi
}

# --- 脚本主入口 ---

# 显示主菜单
show_menu() {
    check_status # 每次显示菜单前都检查一次状态
    
    clear
    echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                     ║${NC}"
    echo -e "${CYAN}║           ${YELLOW}PortProxy 一键安装管理脚本${CYAN}           ║${NC}"
    echo -e "${CYAN}║                                                     ║${NC}"
    echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${NC}"
    echo
    printf "  %s %-30s\n" "当前状态:" "$INSTALL_STATUS"
    echo

    # 根据安装状态动态显示菜单项
    if $IS_INSTALLED; then
        echo -e "  ${GREEN}1.${NC} 重新安装 PortProxy"
        echo -e "  ${GREEN}2.${NC} 卸载 PortProxy"
    else
        echo -e "  ${GREEN}1.${NC} 安装 PortProxy"
        echo -e "  ${DIM}2. 卸载 PortProxy (未安装)${NC}"
    fi
    echo -e "  ---------------------------------------------------"
    echo -e "  ${GREEN}0.${NC} 退出脚本"
    echo
    read -p "$(echo -e "${CYAN}请输入选项 [0-2]: ${NC}")" choice < /dev/tty
}

# 主函数
main() {
    check_root
    check_systemd

    if [[ "$1" == "install" ]]; then
        do_install; exit 0
    elif [[ "$1" == "uninstall" ]]; then
        check_status
        do_uninstall; exit 0
    fi
    
    while true; do
        show_menu
        case $choice in
            1) do_install; break ;;
            2) 
                if $IS_INSTALLED; then
                    do_uninstall
                else
                    error_msg "PortProxy 未安装，无法执行卸载操作。"
                    sleep 1.5
                fi
                break
                ;;
            0) echo "退出脚本。"; exit 0 ;;
            *) error_msg "无效的选项，请重新输入。"; sleep 1.5 ;;
        esac
    done
}

main "$@"
