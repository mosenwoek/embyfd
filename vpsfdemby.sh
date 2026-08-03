#!/usr/bin/env bash

set -Eeuo pipefail

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
RESET="\033[0m"

info() { echo -e "${GREEN}[INFO]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
err() { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
step() { echo -e "\n${BLUE}==== $* ====${RESET}"; }

[[ $EUID -eq 0 ]] || err "请使用 root 用户运行"

ACME="$HOME/.acme.sh/acme.sh"
SSL_DIR="/etc/nginx/ssl"
WWW_DIR="/var/www/html"

normalize_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        url="http://${url}"
    fi
    echo "$url"
}

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1 ]] && [[ "$1" -le 65535 ]]
}

pkg_setup() {
    if command -v apt-get >/dev/null 2>&1; then
        PKG_UPDATE="apt-get update -y"
        PKG_INSTALL="apt-get install -y"
        OS_FAMILY="debian"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_UPDATE="dnf makecache -y"
        PKG_INSTALL="dnf install -y"
        OS_FAMILY="rhel"
    elif command -v yum >/dev/null 2>&1; then
        PKG_UPDATE="yum makecache -y"
        PKG_INSTALL="yum install -y"
        OS_FAMILY="rhel"
    else
        err "不支持的系统，仅支持 Debian/Ubuntu/CentOS/RHEL"
    fi
}

pause_confirm() {
    read -rp "确认继续？[y/N]: " c
    [[ "$c" == "y" || "$c" == "Y" ]] || err "已取消"
}

detect_nginx_conf() {
    if [[ -d /etc/nginx/sites-available ]]; then
        NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"
        NGINX_LINK="/etc/nginx/sites-enabled/${DOMAIN}.conf"
    else
        NGINX_CONF="/etc/nginx/conf.d/${DOMAIN}.conf"
        NGINX_LINK=""
    fi
}

step "填写基础信息"

read -rp "请输入域名，例如 emby.example.com: " DOMAIN
[[ -n "$DOMAIN" ]] || err "域名不能为空"

read -rp "请输入通知邮箱: " EMAIL
[[ -n "$EMAIL" ]] || err "邮箱不能为空"

read -rp "请输入 HTTPS 监听端口，默认 443: " HTTPS_PORT
HTTPS_PORT="${HTTPS_PORT:-443}"
valid_port "$HTTPS_PORT" || err "端口不合法"

echo
echo "请选择部署方式："
echo "  1) 单体部署"
echo "  2) 前后端分离"
read -rp "请选择 [1/2]: " ARCH

SPLIT_MODE="no"
EMBY_BACKEND=""
EMBY_FRONTEND=""

case "$ARCH" in
    1)
        read -rp "请输入 Emby 后端地址，例如 127.0.0.1:8096: " EMBY_BACKEND
        [[ -n "$EMBY_BACKEND" ]] || err "后端地址不能为空"
        EMBY_BACKEND="$(normalize_url "$EMBY_BACKEND")"
        ;;
    2)
        SPLIT_MODE="yes"
        read -rp "请输入 Emby 后端 API 地址，例如 127.0.0.1:8096: " EMBY_BACKEND
        [[ -n "$EMBY_BACKEND" ]] || err "后端地址不能为空"
        EMBY_BACKEND="$(normalize_url "$EMBY_BACKEND")"

        read -rp "请输入 Emby 前端 Web 地址，例如 127.0.0.1:8080，留空则同后端: " EMBY_FRONTEND
        if [[ -n "$EMBY_FRONTEND" ]]; then
            EMBY_FRONTEND="$(normalize_url "$EMBY_FRONTEND")"
        else
            EMBY_FRONTEND="$EMBY_BACKEND"
        fi
        ;;
    *)
        err "无效选择"
        ;;
esac

echo
echo "请选择证书申请方式："
echo "  1) HTTP-01 验证"
echo "  2) DNS-01 Cloudflare"
echo "  3) DNS-01 阿里云"
echo "  4) DNS-01 腾讯云"
echo "  5) DNS-01 DNSPod"
echo "  6) DNS-01 手动 TXT"
read -rp "请选择 [1-6]: " CERT_MODE

HTTP_MODE="no"
MANUAL_DNS="no"
DNS_PROVIDER=""

case "$CERT_MODE" in
    1)
        HTTP_MODE="yes"
        ;;
    2)
        DNS_PROVIDER="dns_cf"
        read -rsp "请输入 Cloudflare API Token: " CF_Token
        echo
        [[ -n "$CF_Token" ]] || err "CF Token 不能为空"
        export CF_Token
        ;;
    3)
        DNS_PROVIDER="dns_ali"
        read -rp "请输入 Ali_Key: " Ali_Key
        read -rsp "请输入 Ali_Secret: " Ali_Secret
        echo
        [[ -n "$Ali_Key" && -n "$Ali_Secret" ]] || err "阿里云密钥不能为空"
        export Ali_Key Ali_Secret
        ;;
    4)
        DNS_PROVIDER="dns_tencent"
        read -rp "请输入 Tencent_SecretId: " Tencent_SecretId
        read -rsp "请输入 Tencent_SecretKey: " Tencent_SecretKey
        echo
        [[ -n "$Tencent_SecretId" && -n "$Tencent_SecretKey" ]] || err "腾讯云密钥不能为空"
        export Tencent_SecretId Tencent_SecretKey
        ;;
    5)
        DNS_PROVIDER="dns_dp"
        read -rp "请输入 DP_Id: " DP_Id
        read -rsp "请输入 DP_Key: " DP_Key
        echo
        [[ -n "$DP_Id" && -n "$DP_Key" ]] || err "DNSPod 密钥不能为空"
        export DP_Id DP_Key
        ;;
    6)
        MANUAL_DNS="yes"
        ;;
    *)
        err "无效选择"
        ;;
esac

echo
echo "========== 配置确认 =========="
echo "域名: $DOMAIN"
echo "邮箱: $EMAIL"
echo "HTTPS 端口: $HTTPS_PORT"
if [[ "$SPLIT_MODE" == "yes" ]]; then
    echo "架构: 前后端分离"
    echo "后端: $EMBY_BACKEND"
    echo "前端: $EMBY_FRONTEND"
else
    echo "架构: 单体部署"
    echo "Emby: $EMBY_BACKEND"
fi
case "$CERT_MODE" in
    1) echo "证书模式: HTTP-01" ;;
    2) echo "证书模式: DNS-01 Cloudflare" ;;
    3) echo "证书模式: DNS-01 阿里云" ;;
    4) echo "证书模式: DNS-01 腾讯云" ;;
    5) echo "证书模式: DNS-01 DNSPod" ;;
    6) echo "证书模式: DNS-01 手动 TXT" ;;
esac
echo "=============================="
pause_confirm

step "安装依赖"

pkg_setup
$PKG_UPDATE

if [[ "$OS_FAMILY" == "debian" ]]; then
    $PKG_INSTALL nginx curl socat cron ca-certificates lsof
else
    $PKG_INSTALL nginx curl socat cronie ca-certificates lsof
fi

mkdir -p "$SSL_DIR" "$WWW_DIR"

step "同步系统时间"

if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-ntp true || true
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable systemd-timesyncd >/dev/null 2>&1 || true
    systemctl restart systemd-timesyncd >/dev/null 2>&1 || true
fi

info "当前系统时间: $(date)"
YEAR="$(date +%Y)"
if [[ "$YEAR" -lt 2024 || "$YEAR" -gt 2030 ]]; then
    warn "系统时间看起来异常，请先校准时间"
fi

step "安装 acme.sh"

if [[ ! -f "$ACME" ]]; then
    curl -fsSL https://get.acme.sh | sh -s email="$EMAIL"
else
    "$ACME" --upgrade || true
fi

[[ -f "$ACME" ]] || err "acme.sh 安装失败"

"$ACME" --set-default-ca --server letsencrypt

step "申请证书"

if [[ "$HTTP_MODE" == "yes" ]]; then
    info "使用 HTTP-01 申请证书"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop nginx >/dev/null 2>&1 || true
    else
        service nginx stop >/dev/null 2>&1 || true
    fi

    "$ACME" --issue --standalone -d "$DOMAIN" --force --keylength ec-256

elif [[ "$MANUAL_DNS" == "yes" ]]; then
    info "使用手动 DNS TXT 验证"
    "$ACME" --issue --dns -d "$DOMAIN" --force --keylength ec-256

else
    info "使用 DNS API: $DNS_PROVIDER"
    "$ACME" --issue --dns "$DNS_PROVIDER" -d "$DOMAIN" --force --keylength ec-256
fi

step "安装证书到 Nginx 目录"

"$ACME" --install-cert -d "$DOMAIN" --ecc \
    --key-file "$SSL_DIR/${DOMAIN}.key" \
    --fullchain-file "$SSL_DIR/${DOMAIN}.cer" \
    --reloadcmd "systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true"

[[ -f "$SSL_DIR/${DOMAIN}.cer" ]] || err "证书文件不存在"
[[ -f "$SSL_DIR/${DOMAIN}.key" ]] || err "私钥文件不存在"

step "生成 Nginx 配置"

detect_nginx_conf

if [[ -f "$NGINX_CONF" ]]; then
    cp "$NGINX_CONF" "${NGINX_CONF}.bak.$(date +%s)"
    info "已备份旧配置"
fi

if [[ "$SPLIT_MODE" == "yes" ]]; then
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root $WWW_DIR;
        default_type "text/plain";
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen $HTTPS_PORT ssl;
    listen [::]:$HTTPS_PORT ssl;
    http2 on;

    server_name $DOMAIN;

    ssl_certificate     $SSL_DIR/${DOMAIN}.cer;
    ssl_certificate_key $SSL_DIR/${DOMAIN}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    client_max_body_size 1024M;

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log  /var/log/nginx/${DOMAIN}_error.log;

    location ~* ^/(emby|mediabrowser|System|Users|Items|Videos|Audio|Images|LiveTv|Sessions|Devices|Plugins|Playback|Sync|DisplayPreferences|ScheduledTasks|Notifications|socket|websocket) {
        proxy_pass $EMBY_BACKEND;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
    }

    location / {
        proxy_pass $EMBY_FRONTEND;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOF
else
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root $WWW_DIR;
        default_type "text/plain";
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen $HTTPS_PORT ssl;
    listen [::]:$HTTPS_PORT ssl;
    http2 on;

    server_name $DOMAIN;

    ssl_certificate     $SSL_DIR/${DOMAIN}.cer;
    ssl_certificate_key $SSL_DIR/${DOMAIN}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    client_max_body_size 1024M;

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log  /var/log/nginx/${DOMAIN}_error.log;

    location / {
        proxy_pass $EMBY_BACKEND;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOF
fi

if [[ -n "$NGINX_LINK" ]]; then
    ln -sf "$NGINX_CONF" "$NGINX_LINK"
fi

step "检查 Nginx 配置"

nginx -t || err "Nginx 配置检测失败"

step "启动 Nginx"

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable nginx >/dev/null 2>&1 || true
    systemctl restart nginx
else
    service nginx restart
fi

sleep 1
ss -lntp | grep -q ":${HTTPS_PORT} " && info "Nginx 已监听 ${HTTPS_PORT} 端口" || warn "未检测到 ${HTTPS_PORT} 端口监听"

step "配置防火墙"

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q active; then
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow "${HTTPS_PORT}/tcp" >/dev/null 2>&1 || true
    info "UFW 已放行 80 和 ${HTTPS_PORT}"
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --add-port=80/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port="${HTTPS_PORT}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    info "firewalld 已放行 80 和 ${HTTPS_PORT}"
else
    warn "未检测到正在运行的 ufw/firewalld，已跳过本机防火墙配置"
fi

warn "云服务商安全组也需要放行 80 和 ${HTTPS_PORT}"

step "测试连通性"

curl -Iks --connect-timeout 8 "$EMBY_BACKEND" >/dev/null || warn "后端连接测试失败，请确认 Emby 地址是否正确"
curl -Ik --connect-timeout 8 "https://127.0.0.1:${HTTPS_PORT}" -H "Host: ${DOMAIN}" >/dev/null || warn "本地 HTTPS 测试失败，请查看 Nginx 日志"

step "生成卸载脚本"

cat > /root/uninstall_emby_proxy.sh <<EOF
#!/usr/bin/env bash
set -e

DOMAIN="$DOMAIN"
NGINX_CONF="$NGINX_CONF"
NGINX_LINK="$NGINX_LINK"
SSL_DIR="$SSL_DIR"
ACME="$ACME"

read -rp "确认卸载 ${DOMAIN} ? [y/N]: " c
[[ "\$c" == "y" || "\$c" == "Y" ]] || exit 0

rm -f "\$NGINX_CONF"
rm -f "\$NGINX_LINK"
rm -f "\$SSL_DIR/\${DOMAIN}.cer"
rm -f "\$SSL_DIR/\${DOMAIN}.key"

if [[ -f "\$ACME" ]]; then
    "\$ACME" --remove -d "\$DOMAIN" --ecc || true
fi

nginx -t && (systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true)

echo "卸载完成"
EOF

chmod +x /root/uninstall_emby_proxy.sh

echo
echo -e "${GREEN}========================================${RESET}"
echo -e "${GREEN}安装完成${RESET}"
echo -e "${GREEN}========================================${RESET}"
echo
if [[ "$HTTPS_PORT" == "443" ]]; then
    echo "访问地址: https://${DOMAIN}"
else
    echo "访问地址: https://${DOMAIN}:${HTTPS_PORT}"
fi
echo "证书文件: $SSL_DIR/${DOMAIN}.cer"
echo "私钥文件: $SSL_DIR/${DOMAIN}.key"
echo "Nginx 配置: $NGINX_CONF"
echo "卸载脚本: /root/uninstall_emby_proxy.sh"
echo
echo "常用命令:"
echo "  nginx -t"
echo "  systemctl reload nginx"
echo "  $ACME --renew -d $DOMAIN --ecc --force"
echo "  tail -f /var/log/nginx/${DOMAIN}_error.log"
echo
warn "如果你用 Cloudflare 橙云，非标准端口可能无法代理。443 或 8443 更稳。"
warn "如果浏览器报 SSL wrong version number，通常是端口上跑了 HTTP，不是 SSL。"
