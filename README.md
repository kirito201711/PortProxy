
# PortProxy - 简单无脑的TCP端口转发工具
![alt text](https://img.shields.io/github/license/kirito201711/PortProxy)
![alt text](https://img.shields.io/badge/language-Shell-blue)
![alt text](https://img.shields.io/badge/OS-Linux%20(systemd)-brightgreen)

还在为转发一个TCP端口而修改复杂的配置文件和重启服务而烦恼吗？

PortProxy 为你提供了一个“傻瓜式”的解决方案。它就是一个带网页管理界面的TCP端口转发工具，让你点几下鼠标就能搞定一切。

### 它有多简单？

*   **一个网页全搞定**: 忘了SSH和命令行吧！打开浏览器，输入密码，就能添加、删除你的端口转发规则。
*   **即时生效**: 新加的规则立刻开始工作，不用重启任何东西。
*   **性能怪兽**: 别看它简单，底层可是“零拷贝”技术，又快又省资源，跑满你的带宽也没问题。
*   **记性很好**: 你设置的规则会自动保存，就算服务器重启了，它也会乖乖地按原样启动。
*   **部署无脑**: 一个命令就能全自动安装好，并设置成开机自启的服务。

如果你只是想快速、简单、稳定地把一个端口的流量转发到另一个地方，PortProxy 就是为你准备的。


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

### ⚙️ 系统要求

在运行脚本之前，请确保您的系统满足以下条件：

* ✅ 一个基于 `systemd` 的 Linux 发行版 (如 Ubuntu 16+, Debian 8+, CentOS 7+)。
* ✅ 拥有 `root` 或 `sudo` 权限。
* ✅ 已安装 `curl` 或 `wget` 用于下载文件。

---


### 📜 许可证

本项目采用 [MIT 许可证](https://github.com/kirito201711/PortProxy/blob/main/LICENSE)。
