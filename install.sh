#!/bin/bash

# PortProxy 安装脚本 (交互式版本)
# 功能:
# 1. 自动下载最新版本的 PortProxy.
# 2. 交互式提示用户输入端口和密码.
# 3. 将文件安装到指定目录.
# 4. 创建 systemd 服务使其可以在后台运行并开机自启.
# 5. 提供卸载功能.

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
NC='\033[0m' # No Color

# --- 辅助函数 ---
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 用于在循环中提示错误信息，但不退出脚本
error_msg() {
    echo -e "${RED}[ERROR]${NC} $1"
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

# --- 主要功能函数 ---

# 下载并解压
download_and_extract() {
    info "正在下载 PortProxy..."
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT # 确保临时目录在退出时被删除

    if command -v curl &> /dev/null; then
        curl -sL "$RELEASE_URL" -o "$TMP_DIR/portProxy.tar.gz" || error "使用 curl 下载失败。"
    elif command -v wget &> /dev/null; then
        wget -qO "$TMP_DIR/portProxy.tar.gz" "$RELEASE_URL" || error "使用 wget 下载失败。"
    else
        error "未找到 curl 或 wget。请先安装其中一个。"
    fi

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
    
    # 获取端口
    while true; do
        read -p "请输入 Web 管理面板的监听端口 [默认: 9090]: " user_admin_port
        user_admin_port=${user_admin_port:-9090}
        if [[ "$user_admin_port" =~ ^[0-9]+$ ]] && [ "$user_admin_port" -ge 1 ] && [ "$user_admin_port" -le 65535 ]; then
            break
        else
            error_msg "端口无效。请输入一个 1-65535 之间的数字。"
        fi
    done

    # 获取密码
    while true; do
        read -s -p "请输入 Web 管理面板的密码 (输入时不可见): " user_admin_password
        echo
        if [ -z "$user_admin_password" ]; then
            error_msg "密码不能为空，请重新输入。"
            continue
        fi
        read -s -p "请再次输入密码以确认: " user_admin_password_confirm
        echo
        if [ "$user_admin_password" == "$user_admin_password_confirm" ]; then
            break
        else
            error_msg "两次输入的密码不匹配，请重试。"
        fi
    done
    info "配置信息已收集完毕。"
}


# 创建 systemd 服务
create_systemd_service() {
    info "正在创建 systemd 服务..."
    
    # 1. 创建服务配置文件
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

    # 2. 根据用户输入创建环境变量文件
    info "正在创建配置文件 ${ENV_FILE}..."
    # 注意：为了安全，将密码用单引号括起来，防止特殊字符导致解析错误
    cat > "$ENV_FILE" << EOF
# PortProxy 启动选项
# 此文件由 install.sh 自动生成
PORTPROXY_OPTS="-admin=:${user_admin_port} -password='${user_admin_password}'"
EOF

    info "重新加载 systemd 配置..."
    systemctl daemon-reload
}

# 卸载程序
uninstall() {
    info "正在卸载 PortProxy..."
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "正在停止 ${SERVICE_NAME} 服务..."
        systemctl stop "$SERVICE_NAME"
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        info "正在禁用 ${SERVICE_NAME} 服务..."
        systemctl disable "$SERVICE_NAME"
    fi

    info "正在删除文件..."
    rm -f "$SERVICE_FILE"
    rm -f "$ENV_FILE"
    rm -f "$BIN_LINK"
    rm -rf "$INSTALL_DIR"
    
    info "重新加载 systemd 配置..."
    systemctl daemon-reload

    info "PortProxy 已成功卸载。"
}

# 主函数
main() {
    check_root
    check_systemd

    if [ "$1" == "uninstall" ]; then
        uninstall
    else
        # 安装流程
        download_and_extract
        install_files
        prompt_for_config
        create_systemd_service
        
        echo
        info "PortProxy 安装成功！"
        echo
        info "配置已根据你的输入自动生成并保存在: ${ENV_FILE}"
        info "你可以使用以下命令管理服务:"
        echo -e "  启动服务: ${GREEN}sudo systemctl start ${SERVICE_NAME}${NC}"
        echo -e "  查看状态: ${GREEN}sudo systemctl status ${SERVICE_NAME}${NC}"
        echo -e "  设置开机自启: ${GREEN}sudo systemctl enable ${SERVICE_NAME}${NC}"
        echo -e "  停止服务: ${GREEN}sudo systemctl stop ${SERVICE_NAME}${NC}"
        echo -e "  查看日志: ${GREEN}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
        echo
        warn "现在就可以启动服务了！"
    fi
}

# --- 脚本入口 ---
main "$@"
