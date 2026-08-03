#!/usr/bin/env bash

set -Eeuo pipefail

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
RESET="\033[0m"

info() { echo -e "${GREEN}[信息]${RESET} $*"; }
warn() { echo -e "${YELLOW}[警告]${RESET} $*"; }
err() { echo -e "${RED}[错误]${RESET} $*"; exit 1; }
step() { echo -e "\n${BLUE}========== $* ==========${RESET}"; }

[[ $EUID -eq 0 ]] || err "请使用 root 用户运行"

clear
cat <<'EOF'
========================================================
        Emby VPS Nginx 反向代理一键脚本
        支持 单体 / 前后端分离 / DNS证书 / HTTP证书
========================================================
EOF

INSTALL_DIR="/etc/nginx/ssl"
WWW_DIR="/var/www/html"
ACME="$HOME/.acme.sh/acme.sh"

check_command() {
    command -v "$1" >/dev/null 2>&1
}

detect_pkg() {
    if check_command apt-get; then
        PKG_UPDATE="apt-get update -y"
        PKG_INSTALL="apt-get install -y"
        OS_FAMILY="debian"
    elif check_command dnf; then
        PKG_UPDATE="dnf makecache -y"
        PKG_INSTALL="dnf install -y"
        OS_FAMILY="rhel"
    elif check_command yum; then
        PKG_UPDATE="yum makecache -y"
        PKG_INSTALL="yum install -y"
        OS_FAMILY="rhel"
    else
        err "不支持当前系统，仅支持 Debian/Ubuntu/CentOS/RHEL"
    fi
}

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

pause_confirm() {
    read -rp "确认继续？[y/N]: " c
    [[ "$c" == "y" || "$c" == "Y" ]] || err "用户取消"
}

step "填写基础信息"

read -rp "请输入反代域名，例如 emby.example.com: " DOMAIN
[[ -n "$DOMAIN" ]] || err "域名不能为空"

read -rp "请输入申请证书邮箱: " EMAIL
[[ -n "$EMAIL" ]] || err "邮箱不能为空"

read -rp "请输入 HTTPS 监听端口，默认 443: " HTTPS_PORT
HTTPS_PORT="${HTTPS_PORT:-443}"
valid_port "$HTTPS_PORT" || err "端口不合法"

echo
echo "请选择 Emby 架构："
echo "  1) 单体部署：前端和后端都在同一个 Emby 地址"
echo "  2) 前后端分离：前端 Web 和后端 API 是两个地址"
read -rp "请选择 [1/2]: " ARCH

SPLIT_MODE="no"
EMBY_BACKEND=""
EMBY_FRONTEND=""

case "$ARCH" in
    1)
        read -rp "请输入 Emby 地址，例如 127.0.0.1:8096 或 http://1.2.3.4:8096: " EMBY_BACKEND
        [[ -n "$EMBY_BACKEND" ]] || err "Emby 地址不能为空"
        EMBY_BACKEND="$(normalize_url "$EMBY_BACKEND")"
        ;;
    2)
        SPLIT_MODE="yes"
        read -rp "请输入 Emby 后端 API 地址，例如 127.0.0.1:8096: " EMBY_BACKEND
        [[ -n "$EMBY_BACKEND" ]] || err "后端 API 地址不能为空"
        EMBY_BACKEND="$(normalize_url "$EMBY_BACKEND")"

        read -rp "请输入 Emby 前端 Web 地址，例如 127.0.0.1:8080，留空则也走后端: " EMBY_FRONTEND
        if [[ -n "$EMBY_FRONTEND" ]]; then
            EMBY_FRONTEND="$(normalize_url "$EMBY_FRONTEND")"
        else
            EMBY_FRONTEND="$EMBY_BACKEND"
        fi
        ;;
    *)
        err "选择无效"
        ;;
esac

echo
echo "请选择证书申请方式："
echo "  1) HTTP-01 验证，需要 80 端口可访问"
echo "  2) DNS-01 Cloudflare API"
echo "  3) DNS-01 阿里云 API"
echo "  4) DNS-01 腾讯云 API"
echo "  5) DNS-01 DNSPod API"
echo "  6) DNS-01 手动添加 TXT 记录"
read -rp "请选择 [1-6]: " CERT_MODE

DNS_PROVIDER=""
HTTP_MODE="no"
MANUAL_DNS="no"

case "$CERT_MODE" in
    1)
        HTTP_MODE="yes"
        ;;
    2)
        DNS_PROVIDER="dns_cf"
        echo
        echo "Cloudflare 推荐使用 API Token，需要 Zone DNS Edit 权限。"
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
        err "证书模式选择无效"
        ;;
esac

echo
echo "================ 配置确认 ================"
echo "域名: $DOMAIN"
echo "邮箱: $EMAIL"
echo "HTTPS 端口: $HTTPS_PORT"
if [[ "$SPLIT_MODE" == "yes" ]]; then
    echo "架构: 前后端分离"
    echo "后端 API: $EMBY_BACKEND"
    echo "前端 Web: $EMBY_FRONTEND"
else
    echo "架构: 单体部署"
    echo "Emby 地址: $EMBY_BACKEND"
fi
case "$CERT_MODE" in
    1) echo "证书方式: HTTP-01" ;;
    2) echo "证书方式: DNS-01 Cloudflare" ;;
    3) echo "证书方式: DNS-01 阿里云" ;;
    4) echo "证书方式: DNS-01 腾讯云" ;;
    5) echo "证书方式: DNS-01 DNSPod" ;;
    6) echo "证书方式: DNS-01 手动 TXT" ;;
esac
echo "=========================================="
pause_confirm

step "安装依赖"

detect_pkg
$PKG_UPDATE

if [[ "$OS_FAMILY" == "debian" ]]; then
    $PKG_INSTALL nginx curl socat cron ca-certificates lsof dnsutils
else
    $PKG_INSTALL nginx curl socat cronie ca-certificates lsof bind-utils
fi

mkdir -p "$INSTALL_DIR" "$WWW_DIR"

step "同步系统时间"

if check_command timedatectl; then
    timedatectl set-ntp true || true
fi

if check_command systemctl; then
    systemctl enable cron --now 2>/dev/null || true
    systemctl enable crond --now 2>/dev/null || true
fi

info "当前系统时间：$(date)"
YEAR="$(date +%Y)"
if [[ "$YEAR" -lt 2024 || "$YEAR" -gt 2030 ]]; then
    warn "当前系统年份异常，证书可能无法正常使用，请先校准 VPS 时间"
fi

step "检查端口占用"

info "当前监听端口："
ss -lntp || true

if ss -lntp | grep -qE ":${HTTPS_PORT}\s"; then
    warn "${HTTPS_PORT} 端口当前已被占用："
    ss -lntp | grep -E ":${HTTPS_PORT}\s" || true
    read -rp "是否继续？如果是 Nginx 占用，脚本会覆盖配置并重启 Nginx。[y/N]: " p
    [[ "$p" == "y" || "$p" == "Y" ]] || err "端口被占用，已退出"
fi

if [[ "$HTTP_MODE" == "yes" ]]; then
    if ss -lntp | grep -qE ":80\s"; then
        warn "80 端口被占用，稍后会临时停止 Nginx 申请证书"
    fi
fi

step "安装或更新 acme.sh"

if [[ ! -f "$ACME" ]]; then
    curl -fsSL https://get.acme.sh | sh -s email="$EMAIL"
else
    "$ACME" --upgrade || true
fi

[[ -f "$ACME" ]] || err "acme.sh 安装失败"

"$ACME" --set-default-ca --server letsencrypt

step "申请证书"

if [[ "$HTTP_MODE" == "yes" ]]; then
    info "使用 HTTP-01 模式强制申请证书"

    if check_command systemctl; then
        systemctl stop nginx 2>/dev/null || true
    else
        service nginx stop 2>/dev/null || true
    fi

    "$ACME" --issue \
        --standalone \
        -d "$DOMAIN" \
        --force \
        --keylength ec-256

elif [[ "$MANUAL_DNS" == "yes" ]]; then
    info "使用手动 DNS TXT 模式申请证书"
    warn "acme.sh 会提示你添加一条 TXT 记录。"
    warn "添加完成并等待生效后，再按回车继续。"

    "$ACME" --issue \
        --dns \
        -d "$DOMAIN" \
        --force \
        --keylength ec-256

else
    info "使用 DNS API 模式强制申请证书：$DNS_PROVIDER"

    "$ACME" --issue \
        --dns "$DNS_PROVIDER" \
        -d "$DOMAIN" \
        --force \
        --keylength ec-256
fi

step "安装证书到 Nginx 目录"

"$ACME" --install-cert \
    -d "$DOMAIN" \
    --ecc \
    --key-file "$INSTALL_DIR/${DOMAIN}.key" \
    --fullchain-file "$INSTALL_DIR/${DOMAIN}.cer" \
    --reloadcmd "systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true"

[[ -f "$INSTALL_DIR/${DOMAIN}.cer" ]] || err "证书文件不存在"
[[ -f "$INSTALL_DIR/${DOMAIN}.key" ]] || err "私钥文件不存在"

step "生成 Nginx 配置"

if [[ -d /etc/nginx/sites-available ]]; then
    NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"
    NGINX_LINK="/etc/nginx/sites-enabled/${DOMAIN}.conf"
else
    NGINX_CONF="/etc/nginx/conf.d/${DOMAIN}.conf"
    NGINX_LINK=""
fi

if [[ -f "$NGINX_CONF" ]]; then
    cp "$NGINX_CONF" "${NGINX_CONF}.bak.$(date +%s)"
    info "已备份旧配置：${NGINX_CONF}.bak"
fi

COMMON_PROXY_HEADERS='
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_connect_timeout 60s;
        proxy_send_timeout 3600s;
        proxy_read_timeout 3600s;

        proxy_buffering off;
        proxy_request_buffering off;
'

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

    ssl_certificate     $INSTALL_DIR/${DOMAIN}.cer;
    ssl_certificate_key $INSTALL_DIR/${DOMAIN}.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    client_max_body_size 1024M;

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log  /var/log/nginx/${DOMAIN}_error.log;

    # Emby API / 媒体 / WebSocket 等后端接口
    location ~* ^/(emby|mediabrowser|System|Users|Items|Videos|Audio|Images|LiveTv|Sessions|Devices|Plugins|Playback|Sync|DisplayPreferences|ScheduledTasks|Notifications|socket|websocket) {
        proxy_pass $EMBY_BACKEND;
$COMMON_PROXY_HEADERS
    }

    # Emby 常见静态接口
    location ~* ^/(web|swagger|dlna|Branding|Packages) {
        proxy_pass $EMBY_BACKEND;
$COMMON_PROXY_HEADERS
    }

    # 前端 Web
    location / {
        proxy_pass $EMBY_FRONTEND;
$COMMON_PROXY_HEADERS
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

    ssl_certificate     $INSTALL_DIR/${DOMAIN}.cer;
    ssl_certificate_key $INSTALL_DIR/${DOMAIN}.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    client_max_body_size 1024M;

    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log  /var/log/nginx/${DOMAIN}_error.log;

    location / {
        proxy_pass $EMBY_BACKEND;
$COMMON_PROXY_HEADERS
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

if check_command systemctl; then
    systemctl enable nginx
    systemctl restart nginx
else
    service nginx restart
fi

sleep 1

if ss -lntp | grep -qE ":${HTTPS_PORT}\s"; then
    info "Nginx 已监听 ${HTTPS_PORT} 端口"
else
    warn "没有检测到 ${HTTPS_PORT} 端口监听，请手动检查 Nginx 状态"
fi

step "配置系统防火墙"

if check_command ufw && ufw status | grep -q active; then
    ufw allow 80/tcp || true
    ufw allow "${HTTPS_PORT}/tcp" || true
    info "UFW 已放行 80 和 ${HTTPS_PORT}"
elif check_command firewall-cmd && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=80/tcp || true
    firewall-cmd --permanent --add-port="${HTTPS_PORT}/tcp" || true
    firewall-cmd --reload || true
    info "firewalld 已放行 80 和 ${HTTPS_PORT}"
else
    warn "未检测到启用中的 ufw/firewalld，跳过系统防火墙配置"
fi

warn "云服务器控制台的安全组也必须放行 80 和 ${HTTPS_PORT}"

step "本地测试"

info "测试后端：$EMBY_BACKEND"
curl -Iks --connect-timeout 8 "$EMBY_BACKEND" || warn "后端测试失败，请确认 Emby 地址是否正确"

info "测试本地 HTTPS："
curl -Ik --connect-timeout 8 "https://127.0.0.1:${HTTPS_PORT}" -H "Host: ${DOMAIN}" || warn "本地 HTTPS 测试失败，请检查 Nginx 日志"

step "生成卸载脚本"

cat > /root/uninstall_emby_proxy.sh <<EOF
#!/usr/bin/env bash
set -e

echo "即将卸载 $DOMAIN 的 Emby 反代配置"
read -rp "确认卸载？[y/N]: " c
[[ "\$c" == "y" || "\$c" == "Y" ]] || exit 0

rm -f "$NGINX_CONF"
rm -f "$NGINX_LINK"
rm -f "$INSTALL_DIR/${DOMAIN}.cer"
rm -f "$INSTALL_DIR/${DOMAIN}.key"

if [[ -f "$ACME" ]]; then
    "$ACME" --remove -d "$DOMAIN" --ecc || true
fi

nginx -t && systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true

echo "卸载完成"
EOF

chmod +x /root/uninstall_emby_proxy.sh

echo
echo -e "${GREEN}=================================================${RESET}"
echo -e "${GREEN}安装完成${RESET}"
echo -e "${GREEN}=================================================${RESET}"
echo
echo "访问地址："
if [[ "$HTTPS_PORT" == "443" ]]; then
    echo "  https://${DOMAIN}"
else
    echo "  https://${DOMAIN}:${HTTPS_PORT}"
fi
echo
echo "Nginx 配置："
echo "  $NGINX_CONF"
echo
echo "证书文件："
echo "  $INSTALL_DIR/${DOMAIN}.cer"
echo "  $INSTALL_DIR/${DOMAIN}.key"
echo
echo "查看日志："
echo "  tail -f /var/log/nginx/${DOMAIN}_error.log"
echo
echo "查看端口："
echo "  ss -lntp | grep ':${HTTPS_PORT}'"
echo
echo "强制续期："
echo "  $ACME --renew -d $DOMAIN --ecc --force"
echo
echo "卸载脚本："
echo "  bash /root/uninstall_emby_proxy.sh"
echo
warn "如果你使用 Cloudflare 橙色云朵，非标准 HTTPS 端口可能不能访问。推荐使用 443 或 8443。"
warn "如果访问提示 SSL wrong version number，说明对应端口不是 ssl listen。"
