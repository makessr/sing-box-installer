#!/bin/bash
set -e

SERVICE_NAME="sing-box"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
BIN_FILE="/usr/local/bin/sing-box"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠️${NC} $1"; }
fail() { echo -e "  ${RED}❌${NC} $1"; }

#################################
# BBR — 启用检测
#################################
enable_bbr() {
    CUR_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    if [ "$CUR_CC" = "bbr" ]; then
        ok "BBR 已启用，跳过"
        return
    fi

    echo "启用 BBR 拥塞控制..."

    modprobe tcp_bbr 2>/dev/null || true
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    cat > /etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system >/dev/null || true

    CUR_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    if [ "$CUR_CC" = "bbr" ]; then
        ok "BBR 已启用"
    else
        warn "BBR 启用失败（当前: $CUR_CC）"
    fi
}

#################################
# 获取最新版本号（缓存）
#################################
get_latest_version() {
    if [ -n "$_CACHED_VERSION" ]; then
        echo "$_CACHED_VERSION"
        return
    fi
    _CACHED_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
    echo "$_CACHED_VERSION"
}

#################################
# 检测 sing-box 是否已安装且最新
#################################
check_installed() {
    if [ ! -f "$BIN_FILE" ]; then
        echo "not_installed"
        return
    fi

    local current
    current=$("$BIN_FILE" version 2>/dev/null | head -1 | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "")
    if [ -z "$current" ]; then
        echo "unknown"
        return
    fi

    local latest_tag
    latest_tag=$(get_latest_version)
    local latest="${latest_tag#v}"

    if [ "$current" = "$latest" ]; then
        echo "latest"
    else
        echo "outdated:$current:$latest"
    fi
}

#################################
# 下载并安装 sing-box
#################################
download_singbox() {
    local version_tag=$1
    local version=${version_tag#v}

    case "$(uname -m)" in
        x86_64) SB_ARCH="amd64" ;;
        aarch64) SB_ARCH="arm64" ;;
        armv7l) SB_ARCH="armv7" ;;
        *) fail "不支持的架构 $(uname -m)"; exit 1 ;;
    esac

    local url="https://github.com/SagerNet/sing-box/releases/download/${version_tag}/sing-box-${version}-linux-${SB_ARCH}.tar.gz"
    echo "下载 sing-box: $url"

    curl -L -o /tmp/singbox.tar.gz "$url"
    mkdir -p /tmp/singbox
    tar -xzf /tmp/singbox.tar.gz -C /tmp/singbox

    local src
    src=$(find /tmp/singbox -type f -name sing-box | head -n1)
    mv "$src" "$BIN_FILE"
    chmod +x "$BIN_FILE"
    rm -rf /tmp/singbox*

    ok "sing-box $version 已安装"
}

#################################
# 检查端口占用
#################################
check_port() {
    local port=$1
    if ss -tlnp "sport = :$port" 2>/dev/null | grep -q .; then
        local prog
        prog=$(ss -tlnp "sport = :$port" 2>/dev/null | grep -oP 'users:\(\("\K[^"]+' || echo "未知")
        warn "端口 $port 已被 $prog 占用"
        return 1
    fi
    return 0
}

#################################
# 生成配置
#################################
generate_config() {
    local port=$1
    local uuid keypair priv_key pub_key short_id
    local hy2_port hy2_pass hy2_sni

    uuid=$(cat /proc/sys/kernel/random/uuid)
    keypair=$($BIN_FILE generate reality-keypair)
    priv_key=$(echo "$keypair" | sed -n 's/^PrivateKey:\s*//p')
    pub_key=$(echo "$keypair" | sed -n 's/^PublicKey:\s*//p')
    short_id=$(openssl rand -hex 4)
    hy2_port=$((port + 1))
    hy2_pass=$(openssl rand -base64 16)

    mkdir -p "$CONFIG_DIR"

    # 自签证书
    openssl req -x509 -nodes -newkey rsa:2048 \
      -days 3650 -keyout "$CONFIG_DIR/hy2.key" -out "$CONFIG_DIR/hy2.crt" \
      -subj "/CN=bing.com"
    ls -la "$CONFIG_DIR/hy2.key" "$CONFIG_DIR/hy2.crt"

    cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$uuid",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "gateway.icloud.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "gateway.icloud.com",
            "server_port": 443
          },
          "private_key": "$priv_key",
          "short_id": ["$short_id"]
        }
      }
    },
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": $hy2_port,
      "up_mbps": 100,
      "down_mbps": 100,
      "users": [
        {
          "password": "$hy2_pass"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "bing.com",
        "key_path": "$CONFIG_DIR/hy2.key",
        "certificate_path": "$CONFIG_DIR/hy2.crt"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

    echo "验证配置文件..."
    $BIN_FILE check -c "$CONFIG_FILE"

    # 输出变量供上层用
    CONFIG_UUID=$uuid
    CONFIG_PUBKEY=$pub_key
    CONFIG_SHORTID=$short_id
    CONFIG_PORT=$port
    CONFIG_HY2_PORT=$hy2_port
    CONFIG_HY2_PASS=$hy2_pass
}

#################################
# 安装入口
#################################
install_singbox() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "请使用 root 运行"
        exit 1
    fi

    echo ""
    echo "=============================="
    echo " Sing-box 一键安装"
    echo "=============================="

    # 1. BBR
    enable_bbr

    # 2. 依赖
    apt update -y && apt install -y curl unzip jq openssl tar

    # 3. 检测 sing-box 状态
    local status
    status=$(check_installed)
    case "$status" in
        latest)
            ok "sing-box 已是最新版，跳过下载"
            ;;
        outdated:*)
            local cur="${status#outdated:}"
            local old_ver="${cur%:*}"
            local new_ver="${cur#*:}"
            warn "sing-box $old_ver → $new_ver"
            download_singbox "$(get_latest_version)"
            ;;
        not_installed)
            echo "下载 sing-box..."
            download_singbox "$(get_latest_version)"
            ;;
        unknown)
            warn "无法检测版本，重新下载..."
            download_singbox "$(get_latest_version)"
            ;;
    esac

    # 4. 端口
    local PORT
    if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; then
        PORT="$1"
        echo "使用指定端口: $PORT"
    else
        # 随机找一个未被占用的端口
        while :; do
            PORT=$((RANDOM % 20001 + 30000))
            check_port "$PORT" && check_port $((PORT + 1)) && break
        done
        echo "使用随机端口: $PORT"
    fi

    # 5. 备份旧配置
    if [ -f "$CONFIG_FILE" ]; then
        local bak="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_FILE" "$bak"
        ok "旧配置已备份: $bak"
    fi

    # 6. 生成配置
    generate_config "$PORT"

    # 7. systemd 服务
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Sing-Box Service
After=network.target

[Service]
ExecStart=$BIN_FILE run -c $CONFIG_FILE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box
    systemctl restart sing-box

    sleep 2
    if systemctl is-active --quiet sing-box; then
        ok "Sing-box 服务运行中"
    else
        fail "服务启动失败，日志如下："
        journalctl -u sing-box -n 20 --no-pager
        exit 1
    fi

    # 8. 输出连接信息
    SERVER_IP=$(curl -s --max-time 5 ipv4.icanhazip.com || curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 api.ip.sb)
    VLESS_URL="vless://${CONFIG_UUID}@${SERVER_IP}:${CONFIG_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=gateway.icloud.com&fp=ios&pbk=${CONFIG_PUBKEY}&sid=${CONFIG_SHORTID}&type=tcp#Reality"
    HY2_URL="hysteria2://${CONFIG_HY2_PASS}@${SERVER_IP}:${CONFIG_HY2_PORT}?sni=bing.com&insecure=1&alpn=h3#Hysteria2"

    echo ""
    echo "=============================="
    echo " ✅ 安装完成"
    echo "=============================="
    echo ""
    echo "VLESS Reality:"
    echo "  端口: $CONFIG_PORT"
    echo "  SNI: gateway.icloud.com"
    echo "  链接:"
    echo "  $VLESS_URL"
    echo ""
    echo "Hysteria2:"
    echo "  端口: $CONFIG_HY2_PORT"
    echo "  SNI: bing.com"
    echo "  密码: $CONFIG_HY2_PASS"
    echo "  链接:"
    echo "  $HY2_URL"
    echo "=============================="
}

#################################
# 卸载
#################################
uninstall_singbox() {
    echo "卸载 sing-box..."
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    rm -rf "$CONFIG_DIR"
    rm -f "$BIN_FILE"
    systemctl daemon-reload
    ok "卸载完成"
}

#################################
# 重启
#################################
restart_singbox() {
    systemctl restart sing-box
    systemctl status sing-box --no-pager
}

#################################
# 状态
#################################
status_singbox() {
    echo "=== 服务状态 ==="
    systemctl status sing-box --no-pager 2>&1
    echo ""
    echo "=== 端口监听 ==="
    ss -tlnp | grep sing-box || warn "未找到 sing-box 监听端口"
    echo ""
    echo "=== 版本 ==="
    if [ -f "$BIN_FILE" ]; then
        $BIN_FILE version 2>/dev/null | head -2
    else
        warn "sing-box 未安装"
    fi
}

#################################
# 更新（仅重下二进制+重启）
#################################
update_singbox() {
    echo "检查更新..."
    local status
    status=$(check_installed)
    case "$status" in
        latest)
            ok "已是最新版"
            return
            ;;
        not_installed)
            warn "sing-box 未安装，执行安装..."
            install_singbox "$1"
            return
            ;;
        outdated:*)
            local cur="${status#outdated:}"
            local old_ver="${cur%:*}"
            local new_ver="${cur#*:}"
            echo "发现新版: $old_ver → $new_ver"
            download_singbox "$(get_latest_version)"
            systemctl restart sing-box
            ok "更新完成"
            ;;
    esac
}

#################################
# 命令分发
#################################
case "$1" in
    install)
        install_singbox "$2"
        ;;
    uninstall)
        uninstall_singbox
        ;;
    restart)
        restart_singbox
        ;;
    status)
        status_singbox
        ;;
    update)
        update_singbox "$2"
        ;;
    *)
        echo "用法:"
        echo "  $0 install [端口]  — 安装/覆盖配置"
        echo "  $0 uninstall       — 卸载"
        echo "  $0 restart         — 重启服务"
        echo "  $0 status          — 查看状态"
        echo "  $0 update [端口]   — 仅更新二进制+重启"
        ;;
esac
