#!/bin/bash

# 日志文件路径
LOGFILE="install.log"
touch $LOGFILE

# 检查命令是否成功执行
check_command() {
    if [ $? -eq 0 ]; then
        echo -e "\e[32m$1: 启动成功\e[0m" | tee -a $LOGFILE
    else
        if command -v $2 &> /dev/null; then
            echo -e "\e[31m$1: 启动失败\e[0m" | tee -a $LOGFILE
        else
            echo -e "\e[33m$1: 未安装\e[0m" | tee -a $LOGFILE
        fi
    fi
}

# 更新系统并安装基本工具
apt-get update &>> $LOGFILE
apt-get install -y curl wget lsb-release ca-certificates gnupg &>> $LOGFILE

# 安装OpenResty
apt-get install -y software-properties-common &>> $LOGFILE
wget -qO - https://openresty.org/package/pubkey.gpg | apt-key add - &>> $LOGFILE
add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" &>> $LOGFILE
apt-get update &>> $LOGFILE
apt-get install -y openresty &>> $LOGFILE
systemctl start openresty &>> $LOGFILE
systemctl enable openresty &>> $LOGFILE
check_command "OpenResty" "openresty"

# 安装PHP 8.3
add-apt-repository ppa:ondrej/php -y &>> $LOGFILE
apt-get update &>> $LOGFILE
apt-get install -y php8.3 php8.3-fpm php8.3-mysql php8.3-cli php8.3-curl php8.3-xml php8.3-mbstring &>> $LOGFILE
systemctl start php8.3-fpm &>> $LOGFILE
systemctl enable php8.3-fpm &>> $LOGFILE
check_command "PHP 8.3" "php8.3-fpm"

# 安装vsftpd
apt-get install -y vsftpd &>> $LOGFILE
systemctl start vsftpd &>> $LOGFILE
systemctl enable vsftpd &>> $LOGFILE
check_command "vsftpd (FTP)" "vsftpd"

# 创建随机FTP用户
FTP_USER="ftpuser_$(date +%s | sha256sum | base64 | head -c 8)"
FTP_PASS=$(openssl rand -base64 12)
useradd -m -s /usr/sbin/nologin $FTP_USER &>> $LOGFILE
echo -e "$FTP_USER:$FTP_PASS" | chpasswd &>> $LOGFILE

# 显示FTP用户信息
echo "FTP用户: $FTP_USER" | tee -a $LOGFILE
echo "FTP密码: $FTP_PASS" | tee -a $LOGFILE

# 配置vsftpd
cat <<EOF >> /etc/vsftpd.conf
listen=NO
listen_ipv6=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
EOF
systemctl restart vsftpd &>> $LOGFILE

# 配置防火墙
ufw allow 21/tcp &>> $LOGFILE
ufw allow 80/tcp &>> $LOGFILE
ufw allow 443/tcp &>> $LOGFILE
ufw allow 21/tcp from any to any proto tcp && ufw allow 80/tcp from any to any proto tcp && ufw allow 443/tcp from any to any proto tcp &>> $LOGFILE
ufw reload &>> $LOGFILE

# 配置简单WAF（阻止常见SQL注入模式）
cat << 'EOF' > /usr/local/openresty/nginx/conf/waf.conf
if ($query_string ~* "union.*select.*\(" ) {
    return 403;
}
if ($query_string ~* "select.*from.*information_schema.tables" ) {
    return 403;
}
if ($query_string ~* "select.*from.*mysql.db" ) {
    return 403;
}
EOF
echo 'include /usr/local/openresty/nginx/conf/waf.conf;' >> /usr/local/openresty/nginx/conf/nginx.conf
systemctl reload openresty &>> $LOGFILE

# 检查服务状态
check_command "OpenResty" "openresty"
check_command "PHP 8.3" "php8.3-fpm"
check_command "vsftpd (FTP)" "vsftpd"

# 完成
echo "部署完成。详细日志请查看 $LOGFILE"
