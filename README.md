## PortProxy 一键安装管理脚本

🚀 一条命令，轻松完成 **PortProxy** 的安装、配置、服务管理与卸载。

本脚本旨在简化 PortProxy 在 Linux 服务器上的部署和日常维护流程，提供一个美观、易用的交互式菜单。

![alt text](https://img.shields.io/github/license/kirito201711/PortProxy)
![alt text](https://img.shields.io/badge/language-Shell-blue)
![alt text](https://img.shields.io/badge/OS-Linux%20(systemd)-brightgreen)

---
### 🚀 快速开始

#### 一键安装命令

打开你的终端，执行以下命令即可启动安装向导：

中国大陆：
```bash
curl -sSL https://gh-proxy.com/https://raw.githubusercontent.com/kirito201711/PortProxy/main/install.sh | bash
```
国际：
```bash
curl -sSL https://raw.githubusercontent.com/kirito201711/PortProxy/main/install.sh | bash
```
---
### ✨ 脚本特性

* **一键安装**: 只需一条命令即可自动下载、安装并配置好 PortProxy。
* **交互式配置**: 无需手动编辑文件，脚本会引导您完成 Web 面板端口和密码的设置。
* **智能代理支持**: 自动提示是否使用 **GitHub 下载代理**，解决国内服务器访问慢的问题，并支持自定义代理地址。
* **自动化服务管理**: 自动创建 `systemd` 服务，实现**开机自启**、**进程守护**。
* **集成化管理菜单**: 提供一个集成的管理面板，可轻松进行 **启动**、**停止**、**重启**、**查看状态**、**查看日志** 等操作。
* **安全可靠的卸载**: 提供**一键卸载**功能，干净彻底地移除所有相关文件和服务，不留残余。
* **美观的用户界面**: 使用颜色和符号优化输出，操作流程清晰明了。

---

### ⚙️ 系统要求

在运行脚本之前，请确保您的系统满足以下条件：

* ✅ 一个基于 `systemd` 的 Linux 发行版 (如 Ubuntu 16+, Debian 8+, CentOS 7+)。
* ✅ 拥有 `root` 或 `sudo` 权限。
* ✅ 已安装 `curl` 或 `wget` 用于下载文件。

---


### 📜 许可证

本项目采用 [MIT 许可证](https://github.com/kirito201711/PortProxy/blob/main/LICENSE)。
