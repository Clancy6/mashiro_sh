#!/bin/bash

LOGFILE="install.log"
exec > >(tee -a "$LOGFILE") 2>&1

# 卸载和初始化功能
function uninstall_services() {
    echo "正在卸载可能已安装的服务..."

    # 停止服务
    systemctl stop openresty php8.2-fpm vsftpd ufw 2>/dev/null

    # 卸载 OpenResty
    apt-get remove --purge -y openresty

    # 卸载 PHP
    apt-get remove --purge -y php8.2 php8.2-fpm php8.2-mysql php8.2-cli php8.2-curl php8.2-xml php8.2-mbstring
    apt-get autoremove -y --purge

    # 卸载 vsftpd
    apt-get remove --purge -y vsftpd

    # 卸载 UFW
    apt-get remove --purge -y ufw

    # 清理残留的配置文件和依赖
    apt-get autoremove -y --purge
    apt-get clean
    rm -rf /etc/php/8.2 /etc/openresty /etc/vsftpd.conf /etc/ufw /var/lib/ufw

    echo "卸载和初始化完成。"
}

# 提示用户确认是否要卸载
read -p "是否卸载已安装的相关服务并初始化系统？[y/N]: " confirm_uninstall
if [[ "$confirm_uninstall" =~ ^[Yy]$ ]]; then
    uninstall_services
else
    echo "跳过卸载和初始化。"
fi

# 更新系统并安装基本工具
apt-get update && apt-get install -y software-properties-common curl wget gnupg2 ca-certificates lsb-release

# 添加 OpenResty 仓库并安装
echo "deb http://openresty.org/package/debian $(lsb_release -sc) openresty" | tee /etc/apt/sources.list.d/openresty.list
wget -qO - https://openresty.org/package/pubkey.gpg | apt-key add -
apt-get update && apt-get install -y openresty

# 启动 OpenResty 并检查状态
systemctl enable openresty
systemctl start openresty
if systemctl status openresty | grep -q "active (running)"; then
    echo -e "\e[32mOpenResty: 启动成功\e[0m"
else
    echo -e "\e[31mOpenResty: 启动失败\e[0m"
fi

# 安装 PHP 8.2
add-apt-repository ppa:ondrej/php -y
apt-get update && apt-get install -y php8.2 php8.2-fpm php8.2-mysql php8.2-cli php8.2-curl php8.2-xml php8.2-mbstring

# 启动 PHP 8.2 并检查状态
systemctl enable php8.2-fpm
systemctl start php8.2-fpm
if systemctl status php8.2-fpm | grep -q "active (running)"; then
    echo -e "\e[32mPHP 8.2: 启动成功\e[0m"
else
    echo -e "\e[31mPHP 8.2: 启动失败\e[0m"
fi

# 安装 vsftpd 并配置
apt-get install -y vsftpd
FTP_USER="ftpuser_$(openssl rand -hex 4)"
FTP_PASS=$(openssl rand -base64 12)
useradd -m -s /bin/bash "$FTP_USER"
echo "$FTP_USER:$FTP_PASS" | chpasswd

# 启动 FTP 并检查状态
systemctl enable vsftpd
systemctl start vsftpd
if systemctl status vsftpd | grep -q "active (running)"; then
    echo -e "\e[32mvsftpd (FTP): 启动成功\e[0m"
    echo "FTP用户: $FTP_USER"
    echo "FTP密码: $FTP_PASS"
else
    echo -e "\e[31mvsftpd (FTP): 启动失败\e[0m"
fi

# 安装并配置 UFW
apt-get install -y ufw
ufw allow 21/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from any to any port 21 proto tcp
ufw enable

# 允许 IPv6 流量
sed -i 's/IPV6=no/IPV6=yes/g' /etc/default/ufw
ufw reload

echo -e "\e[33m安装过程日志保存在 $LOGFILE\e[0m"
