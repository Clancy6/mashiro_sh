#!/bin/bash

# 定义颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 创建日志目录和文件
log_dir="./mashiro_sh"
mkdir -p "$log_dir"
log_file="$log_dir/$(date +%Y-%m-%d_%H:%M:%S).log"

# 重定向所有输出到日志文件
exec > >(tee -a "$log_file") 2>&1

# 显示脚本名称和网址
show_banner() {
    clear
    echo
    echo -e "  __  __           _     _               _     "
    echo -e " |  \/  |         | |   (_)             | |    "
    echo -e " | \  / | __ _ ___| |__  _ _ __ ___  ___| |__  "
    echo -e " | |\/| |/ _\` / __| '_ \| | '__/ _ \/ __| '_ \ "
    echo -e " | |  | | (_| \__ \ | | | | | | (_) \__ \ | | |"
    echo -e " |_|  |_|\__,_|___/_| |_|_|_|  \___/|___/_| |_|"
    echo
    echo -e "${GREEN}官网: https://mashiro.ru/mashiro_sh/${PLAIN}"
    echo
}

# 修复 locale 设置
fix_locale() {
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y locales
    elif [ -f /etc/redhat-release ]; then
        yum install -y glibc-common
    fi

    # 确保 en_US.UTF-8 locale 存在
    if ! locale -a | grep -q en_US.UTF-8; then
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
        locale-gen
    fi

    # 设置系统默认 locale
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 || true

    # 更新当前会话的环境变量
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    echo "Locale 设置已更新。当前 locale 设置："
    locale
}

# 检测系统版本
check_release() {
    if [ -f /etc/redhat-release ]; then
        release="centos"
    elif cat /etc/issue | grep -Eqi "debian"; then
        release="debian"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
    else
        echo -e "${RED}不支持当前操作系统${PLAIN}" && exit 1
    fi
}

# 安装基础环境
install_base() {
    if [ "$release" == "centos" ]; then
        yum install -y epel-release
        yum install -y wget curl git unzip tar gcc gcc-c++ make
    else
        apt-get update
        apt-get install -y wget curl git unzip tar gcc g++ make
    fi
}

# 安装OpenResty+PHP+FTP+WAF环境
install_env() {
    read -p "请输入要安装的PHP版本,多个版本以空格分隔(默认: 8.3): " install_versions
    install_versions=${install_versions:-8.3}

    read -p "请输入FTP用户名(默认: 随机生成): " ftp_user
    ftp_user=${ftp_user:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)}

    read -p "请输入FTP密码(默认: 随机生成): " ftp_pass
    ftp_pass=${ftp_pass:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9!@#$%^&*-+=' | fold -w 16 | head -n 1)}

    install_base
    
    # 安装OpenResty
    if [ "$release" == "centos" ]; then
        yum -y install yum-utils
        yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
        yum -y install openresty
    else
        apt-get -y install --no-install-recommends wget gnupg ca-certificates
        wget -O - https://openresty.org/package/pubkey.gpg | apt-key add -
        codename=$(lsb_release -c | cut -f2)
        echo "deb http://openresty.org/package/debian $codename openresty" \
            | tee /etc/apt/sources.list.d/openresty.list
        apt-get update
        apt-get -y install openresty
    fi

    # 安装用户选择的多个PHP版本
    for ver in $install_versions
    do
        if [ "$release" == "centos" ]; then
            yum -y install http://rpms.remirepo.net/enterprise/remi-release-7.rpm
            yum -y install yum-utils
            yum-config-manager --enable remi-php${ver//./}
            yum -y install php php-fpm php-cli php-common
        else
            apt-get -y install software-properties-common
            add-apt-repository -y ppa:ondrej/php
            apt-get update
            apt-get -y install php${ver} php${ver}-fpm php${ver}-cli php${ver}-common 
        fi
    done

    # 设置默认PHP版本为第一个安装的版本
    default_ver=$(echo $install_versions | cut -d' ' -f1)
    if [ "$release" == "centos" ]; then
        update-alternatives --set php /usr/bin/php$default_ver
    else
        update-alternatives --set php /usr/bin/php$default_ver
    fi
    echo "已将默认PHP版本设置为: php$default_ver"

    # 安装并配置FTP服务
    if [ "$release" == "centos" ]; then
        yum -y install vsftpd
    else
        apt-get -y install vsftpd
    fi

    # 创建FTP用户并设置主目录为网站根目录
    ftp_dir="/usr/local/openresty/nginx/html"
    useradd -d $ftp_dir -s /sbin/nologin $ftp_user
    echo "$ftp_user:$ftp_pass" | chpasswd

    # 安装并配置WAF (使用ModSecurity for NGINX)
    if [ "$release" == "centos" ]; then
        yum -y install nginx-mod-http-modsecurity
    else
        apt-get -y install nginx-module-modsecurity
    fi

    git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity /tmp/ModSecurity
    git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git /tmp/ModSecurity-nginx

    # 编译并安装ModSecurity-nginx模块
    cd /tmp/ModSecurity
    ./build.sh
    ./configure
    make
    make install

    # 配置OpenResty
    nginx_conf="/usr/local/openresty/nginx/conf/nginx.conf"
    sed -i 's/worker_processes  1;/worker_processes  auto;/' $nginx_conf
    sed -i '/http {/a \    client_max_body_size 50m;' $nginx_conf
    
    # 配置 PHP-FPM
    if [ "$release" == "centos" ]; then
        fpm_conf="/etc/php-fpm.d/www.conf"
    else
        fpm_conf="/etc/php/${default_ver}/fpm/pool.d/www.conf"
    fi
    sed -i 's/^user = www-data/user = nginx/' $fpm_conf
    sed -i 's/^group = www-data/group = nginx/' $fpm_conf
    sed -i 's/^listen = \/run\/php\/php'"$default_ver"'-fpm.sock/listen = 127.0.0.1:9000/' $fpm_conf

    # 启动并检查服务状态
    services=("openresty" "php${default_ver}-fpm" "vsftpd")

    for service in "${services[@]}"
    do
        systemctl enable $service
        systemctl start $service
        if systemctl is-active --quiet $service; then
            echo -e "${GREEN}$service 启动成功${PLAIN}"
        else
            echo -e "${RED}$service 启动失败${PLAIN}"
        fi
    done

    echo "============================"
    echo "OpenResty + 多PHP版本 + FTP + WAF 环境一键部署脚本执行完毕!"
    echo "网站根目录为: $ftp_dir"
    echo "FTP登录信息如下:"
    echo "主机: $(curl -s ipv4.icanhazip.com || echo '获取失败')"
    echo "用户名: $ftp_user"
    echo "密码: $ftp_pass"
    echo "日志文件位置: $log_file"
    echo "============================"
}

# 主程序
main() {
    show_banner
    check_release
    fix_locale
    install_env
}

main
