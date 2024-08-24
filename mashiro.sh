#!/bin/bash

# 定义颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

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

    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    echo "Locale 设置已更新。"
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
    read -p "请输入要安装的PHP版本,多个版本以空格分隔(默认: 83): " install_versions
    install_versions=${install_versions:-83}

    read -p "请输入FTP用户名(默认: 随机生成): " ftp_user
    ftp_user=${ftp_user:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)}

    read -p "请输入FTP密码(默认: 随机生成): " ftp_pass
    ftp_pass=${ftp_pass:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9!@#$%^&*-+=' | fold -w 16 | head -n 1)}

    install_base
    
    # 安装OpenResty
    if [ "$release" == "centos" ]; then
        yum -y install pcre-devel openssl-devel gcc curl
        wget https://openresty.org/package/centos/openresty.repo -O /etc/yum.repos.d/openresty.repo
        yum -y install openresty
    else
        apt-get -y install libpcre3-dev libssl-dev perl make build-essential curl zlib1g-dev
        wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
        echo "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/openresty.list
        apt-get update 
        apt-get -y install openresty
    fi

    # 从PHP官方API获取可用PHP版本
    php_versions=$(curl -s https://www.php.net/releases/index.php?json&version=8 | grep -oP '"\K[0-9]+' | tr '\n' ' ')
    echo "检测到以下可用的PHP版本: $php_versions"

    # 安装用户选择的多个PHP版本
    for ver in $install_versions
    do
        if [[ $php_versions =~ $ver ]]; then
            if [ "$release" == "centos" ]; then
                yum -y install php$ver php$ver-fpm php$ver-cli php$ver-common
            else
                apt-get -y install php$ver php$ver-fpm php$ver-cli php$ver-common 
            fi
        else
            echo "跳过安装无效的PHP版本: $ver"
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

    # 安装并配置WAF
    if [ "$release" == "centos" ]; then
        yum -y install mod_security
        sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/httpd/conf.d/mod_security.conf
        sed -i 's/SecRequestBodyAccess On/SecRequestBodyAccess Off/' /etc/httpd/conf.d/mod_security.conf
        git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git /etc/httpd/crs
        cd /etc/httpd/crs
        cp crs-setup.conf.example crs-setup.conf
        echo "Include /etc/httpd/crs/crs-setup.conf" >> /etc/httpd/conf/httpd.conf
        echo "Include /etc/httpd/crs/rules/*.conf" >> /etc/httpd/conf/httpd.conf
    else
        apt-get -y install libapache2-mod-security2
        sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf
        sed -i 's/SecRequestBodyAccess On/SecRequestBodyAccess Off/' /etc/modsecurity/modsecurity.conf
        git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git /etc/modsecurity/crs
        cd /etc/modsecurity/crs  
        cp crs-setup.conf.example crs-setup.conf
        echo "Include /etc/modsecurity/crs/crs-setup.conf" >> /etc/apache2/apache2.conf
        echo "Include /etc/modsecurity/crs/rules/*.conf" >> /etc/apache2/apache2.conf
    fi

    # 配置OpenResty
    nginx_conf="/usr/local/openresty/nginx/conf/nginx.conf"
    sed -i 's/worker_processes  1;/worker_processes  auto;/' $nginx_conf
    sed -i '/http {/a \    client_max_body_size 50m;' $nginx_conf
    
    # 配置 PHP-FPM
    fpm_conf="/etc/php/$default_ver/fpm/pool.d/www.conf"
    sed -i 's/^user = www-data/user = nginx/' $fpm_conf
    sed -i 's/^group = www-data/group = nginx/' $fpm_conf
    sed -i 's/^listen = \/run\/php\/php'"$default_ver"'-fpm.sock/listen = 127.0.0.1:9000/' $fpm_conf

    # 启动并检查服务状态
    services=("openresty" "php$default_ver-fpm" "vsftpd")
    if [ "$release" == "centos" ]; then
        services+=("httpd")
    else
        services+=("apache2")
    fi

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
