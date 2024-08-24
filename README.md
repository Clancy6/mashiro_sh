# Mashiro.sh - 新一代NAT小鸡环境一键部署脚本，mjjの福音！

*请注意：此脚本适合全新的NAT VPS实例，在运行脚本前仅安装curl即可。脚本可能会与已有的运行环境造成不可逆的冲突！*

## 脚本内容
OpenResty+PHP+FTP+WAF环境一键部署（适用于拥有**共享ipv4**、**独立ipv6**的小鸡）

## 使用方法
### Debian / Ubuntu 安装下载工具
如果您使用的是 Debian 或 Ubuntu 系统，请按照以下步骤设置必要环境：

执行以下命令更新软件包列表并安装 curl 工具：
   ```bash
   apt update -y && apt install -y curl
   ```
### CentOS 安装下载工具

如果您使用的是 CentOS 系统，请按照以下步骤安装下载工具：

执行以下命令更新软件包列表并安装 curl 工具：
   ```bash
   yum install -y curl
   ```
### 一键脚本
```bash
curl -sL https://raw.githubusercontent.com/Clancy6/mashiro_sh/main/mashiro.sh -o mashiro.sh && chmod +x mashiro.sh && ./mashiro.sh
```

