#!/bin/bash
set -e

# ===================== 颜色定义 =====================
sred='\033[5;31m'
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}

# ===================== 常量 =====================
SERVICE_NAME="sing-box"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
INFO_FILE="${CONFIG_DIR}/info.txt"
PUBKEY_FILE="${CONFIG_DIR}/.pubkey"
BIN_FILE="/usr/local/bin/sing-box"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ===================== 系统信息检测 =====================
get_sysinfo(){
    if [[ -f /etc/redhat-release ]]; then
        release="Centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="Debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="Ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="Centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="Debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="Ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="Centos"
    else
        red "不支持当前系统，仅支持 Ubuntu/Debian/CentOS" && exit 1
    fi
    version=$(uname -r | cut -d "-" -f1)
    case $(uname -m) in
        aarch64) cpu=arm64;;
        x86_64)  cpu=amd64;;
        armv7l)  cpu=armv7;;
        *)       red "不支持 $(uname -m) 架构" && exit 1;;
    esac
    [[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
    if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
        bbr_val=$(sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}')
    else
        bbr_val="未启用"
    fi
    v4=$(curl -s4m5 icanhazip.com -k 2>/dev/null || true)
    v6=$(curl -s6m5 icanhazip.com -k 2>/dev/null || true)
    if [[ -z $v4 ]]; then
        vps_ipv4='无IPV4'
        vps_ipv6="$v6"
    elif [[ -n $v4 && -n $v6 ]]; then
        vps_ipv4="$v4"
        vps_ipv6="$v6"
    else
        vps_ipv4="$v4"
        vps_ipv6='无IPV6'
    fi
}

# ===================== 状态检测（install.sh 风格） =====================
check_status() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        return 2
    fi
    temp=$(systemctl is-active sing-box 2>/dev/null | grep -w active)
    if [[ x"${temp}" == x"active" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled sing-box 2>/dev/null)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    local _st
    if check_status; then _st=0; else _st=$?; fi
    if [[ $_st != 2 ]]; then
        yellow "sing-box 已安装，可先卸载再安装" && sleep 2
        return 1
    fi
    return 0
}

check_install() {
    local _st
    if check_status; then _st=0; else _st=$?; fi
    if [[ $_st == 2 ]]; then
        yellow "未安装 sing-box，请先安装" && sleep 2
        return 1
    fi
    return 0
}

show_status() {
    local _st
    if check_status; then _st=0; else _st=$?; fi
    case $_st in
        0)  echo -e "sing-box 状态: ${blue}已运行${plain}"; show_enable_status;;
        1)  echo -e "sing-box 状态: ${yellow}未运行${plain}"; show_enable_status;;
        2)  echo -e "sing-box 状态: ${red}未安装${plain}";;
    esac
    show_bin_status
}

show_enable_status() {
    local _en
    if check_enabled; then _en=0; else _en=$?; fi
    if [[ $_en == 0 ]]; then
        echo -e "sing-box 自启: ${blue}是${plain}"
    else
        echo -e "sing-box 自启: ${red}否${plain}"
    fi
}

show_bin_status() {
    if [[ -f "$BIN_FILE" ]]; then
        local ver
        ver=$("$BIN_FILE" version 2>/dev/null | head -1 | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "未知")
        echo -e "sing-box 版本: ${blue}${ver}${plain}"
    else
        echo -e "sing-box 版本: ${red}未安装${plain}"
    fi
}

# ===================== BBR — 幂等检测 =====================
enable_bbr() {
    CUR_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    if [ "$CUR_CC" = "bbr" ]; then
        green "BBR 已启用，跳过"
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
        green "BBR 已启用"
    else
        yellow "BBR 启用失败（当前: $CUR_CC）"
    fi
}

# ===================== sing-box 版本检测（幂等） =====================
get_latest_version() {
    if [ -n "$_CACHED_VERSION" ]; then
        echo "$_CACHED_VERSION"
        return
    fi
    _CACHED_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name' || echo "")
    echo "$_CACHED_VERSION"
}

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

# ===================== 下载 sing-box =====================
download_singbox() {
    local version_tag=$1
    local version=${version_tag#v}
    case "$(uname -m)" in
        x86_64)  SB_ARCH="amd64";;
        aarch64) SB_ARCH="arm64";;
        armv7l)  SB_ARCH="armv7";;
        *)       red "不支持的架构 $(uname -m)"; exit 1;;
    esac
    local url="https://github.com/SagerNet/sing-box/releases/download/${version_tag}/sing-box-${version}-linux-${SB_ARCH}.tar.gz"
    green "下载 sing-box: $url"
    curl -L -o /tmp/singbox.tar.gz "$url" 2>&1 | tail -1
    mkdir -p /tmp/singbox
    tar -xzf /tmp/singbox.tar.gz -C /tmp/singbox
    local src
    src=$(find /tmp/singbox -type f -name sing-box | head -n1)
    mv "$src" "$BIN_FILE"
    chmod +x "$BIN_FILE"
    rm -rf /tmp/singbox*
    green "sing-box $version 已安装"
}

# ===================== 端口检测 =====================
check_port() {
    local port=$1
    # ss -tlnp 输出有表头行，grep LISTEN 排除表头
    if ss -tlnp "sport = :$port" 2>/dev/null | grep -q LISTEN; then
        local prog
        prog=$(ss -tlnp "sport = :$port" 2>/dev/null | grep -oP 'users:\(\("\K[^"]+' || echo "未知")
        yellow "端口 $port 已被 $prog 占用"
        return 1
    fi
    return 0
}

# ===================== 生成配置 =====================
generate_config() {
    local port=$1
    local uuid keypair priv_key pub_key short_id
    local hy2_port hy2_pass tuic_port tuic_pass

    uuid=$($BIN_FILE generate uuid)
    keypair=$($BIN_FILE generate reality-keypair)
    priv_key=$(echo "$keypair" | sed -n 's/^PrivateKey:\s*//p')
    pub_key=$(echo "$keypair" | sed -n 's/^PublicKey:\s*//p')
    short_id=$($BIN_FILE generate rand --hex 4)
    hy2_port=$((port + 1))
    hy2_pass=$($BIN_FILE generate rand --base64 16)
    tuic_port=$((port + 2))
    tuic_pass=$($BIN_FILE generate rand --base64 16)

    mkdir -p "$CONFIG_DIR"

    # 自签证书
    openssl req -x509 -nodes -newkey rsa:2048 \
      -days 3650 -keyout "$CONFIG_DIR/hy2.key" -out "$CONFIG_DIR/hy2.crt" \
      -subj "/CN=bing.com" 2>/dev/null

    # 计算证书 SHA256（HY2 客户端校验用）
    SHA256=$(openssl x509 -in "$CONFIG_DIR/hy2.crt" -outform DER | sha256sum | awk '{print $1}')

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
    },
    {
      "type": "tuic",
      "listen": "::",
      "listen_port": $tuic_port,
      "users": [
        {
          "uuid": "$uuid",
          "password": "$tuic_pass"
        }
      ],
      "congestion_control": "bbr",
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
      "type": "direct",
      "tag": "direct-out"
    }
  ],
  "route": {
    "final": "direct-out"
  }
}
EOF

    echo "验证配置文件..."
    $BIN_FILE check -c "$CONFIG_FILE"

    # iptables 放行端口
    for p in $port $hy2_port $tuic_port; do
        iptables -C INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport $p -j ACCEPT
        iptables -C INPUT -p udp --dport $p -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport $p -j ACCEPT
    done
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null
    fi

    CONFIG_UUID=$uuid
    CONFIG_PUBKEY=$pub_key
    CONFIG_SHORTID=$short_id
    CONFIG_PORT=$port
    CONFIG_SHA256=$SHA256
    CONFIG_HY2_PORT=$hy2_port
    CONFIG_HY2_PASS=$hy2_pass
    CONFIG_TUIC_PORT=$tuic_port
    CONFIG_TUIC_PASS=$tuic_pass
}

# ===================== 安装入口 =====================
install_singbox() {
    if [ "$(id -u)" -ne 0 ]; then
        red "请使用 root 运行"
        exit 1
    fi

    [[ -n "$TERM" ]] && clear
    logo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    blue "            Sing-box 一键安装脚本"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

    # 1. BBR
    enable_bbr

    # 2. 依赖
    apt update -y && apt install -y curl unzip jq openssl tar virt-what

    # 3. 检测 sing-box 状态（幂等）
    local status
    status=$(check_installed)
    case "$status" in
        latest)
            green "sing-box 已是最新版，跳过下载"
            ;;
        outdated:*)
            local cur="${status#outdated:}"
            local old_ver="${cur%:*}"
            local new_ver="${cur#*:}"
            yellow "sing-box $old_ver → $new_ver"
            download_singbox "$(get_latest_version)"
            ;;
        not_installed)
            echo "下载 sing-box..."
            download_singbox "$(get_latest_version)"
            ;;
        unknown)
            yellow "无法检测版本，重新下载..."
            download_singbox "$(get_latest_version)"
            ;;
    esac

    # 4. 端口
    local PORT
    if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; then
        PORT="$1"
        blue "使用指定端口: $PORT"
    else
        while :; do
            PORT=$((RANDOM % 20001 + 30000))
            check_port "$PORT" && check_port $((PORT + 1)) && check_port $((PORT + 2)) && break
        done
        blue "使用随机端口: $PORT"
    fi

    # 5. 备份旧配置
    if [ -f "$CONFIG_FILE" ]; then
        local bak="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_FILE" "$bak"
        green "旧配置已备份: $bak"
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
        green "Sing-box 服务运行中"
    else
        red "服务启动失败，日志如下："
        journalctl -u sing-box -n 20 --no-pager
        exit 1
    fi

    # 8. 获取 IP
    SERVER_IP=$(curl -s --max-time 5 ipv4.icanhazip.com || curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 api.ip.sb)
    VLESS_URL="vless://${CONFIG_UUID}@${SERVER_IP}:${CONFIG_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=gateway.icloud.com&fp=chrome&pbk=${CONFIG_PUBKEY}&sid=${CONFIG_SHORTID}&type=tcp&headerType=none#Reality"
    HY2_URL="hysteria2://${CONFIG_HY2_PASS}@${SERVER_IP}:${CONFIG_HY2_PORT}?security=tls&alpn=h3&sni=bing.com&pinSHA256=${CONFIG_SHA256}#Hysteria2"
    TUIC_URL="tuic://${CONFIG_UUID}:${CONFIG_TUIC_PASS}@${SERVER_IP}:${CONFIG_TUIC_PORT}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=bing.com&insecure=1#Tuic"

    # 9. 输出（install.sh 风格）
    echo "----------------------------------------------------------------------"
    green "Sing-box 安装成功"
    echo "----------------------------------------------------------------------"
    echo ""
    blue "VLESS Reality 节点："
    echo "  端口: $CONFIG_PORT"
    echo "  UUID: $CONFIG_UUID"
    echo "  SNI: gateway.icloud.com"
    echo "  PublicKey: $CONFIG_PUBKEY"
    echo "  ShortId: $CONFIG_SHORTID"
    echo "  链接:"
    green "  $VLESS_URL"
    echo ""
    blue "Hysteria2 节点："
    echo "  端口: $CONFIG_HY2_PORT"
    echo "  密码: $CONFIG_HY2_PASS"
    echo "  SNI: bing.com"
    echo "  pinSHA256: $CONFIG_SHA256"
    echo "  链接:"
    green "  $HY2_URL"
    echo ""
    blue "TUIC 节点："
    echo "  端口: $CONFIG_TUIC_PORT"
    echo "  UUID: $CONFIG_UUID"
    echo "  密码: $CONFIG_TUIC_PASS"
    echo "  SNI: bing.com"
    echo "  链接:"
    green "  $TUIC_URL"
    echo "----------------------------------------------------------------------"
    echo ""
    # 10. 保存配置信息
    cat > "$INFO_FILE" <<EOF
VLESS_PORT=$CONFIG_PORT
VLESS_UUID=$CONFIG_UUID
VLESS_PUBKEY=$CONFIG_PUBKEY
VLESS_SHORTID=$CONFIG_SHORTID
HY2_PORT=$CONFIG_HY2_PORT
HY2_PASS=$CONFIG_HY2_PASS
HY2_SHA256=$CONFIG_SHA256
TUIC_PORT=$CONFIG_TUIC_PORT
TUIC_PASS=$CONFIG_TUIC_PASS
SERVER_IP=$SERVER_IP
EOF
    green "配置信息已保存到: $INFO_FILE"
    echo "$pub_key" > "$PUBKEY_FILE"
    green "PublicKey 已保存到: $PUBKEY_FILE"

    # 刷新系统信息并显示状态
    get_sysinfo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "系统:${blue}$release${plain}  内核:${blue}$version${plain}  处理器:${blue}$cpu${plain}  虚拟化:${blue}$vi${plain}  BBR算法:${blue}$bbr_val${plain}"
    echo -e "本地IPV4地址：${blue}$vps_ipv4${plain}  本地IPV6地址：${blue}$vps_ipv6${plain}"
    echo "------------------------------------------------------------------------------------"
    show_status
    echo "------------------------------------------------------------------------------------"
    echo ""
    green "脚本快捷使用方式：bash reality.sh"
    echo ""
}

# ===================== 卸载 =====================
uninstall_singbox() {
    yellow "是否卸载 sing-box？（回车确认，Ctrl+C 取消）"
    readp "" confirm
    echo "卸载 sing-box..."
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    rm -rf "$CONFIG_DIR"
    rm -f "$BIN_FILE"
    systemctl daemon-reload
    green "卸载完成"
}

# ===================== 重启 =====================
restart_singbox() {
    systemctl restart sing-box
    sleep 2
    if systemctl is-active --quiet sing-box; then
        green "Sing-box 重启成功"
    else
        red "重启失败，查看日志："
        journalctl -u sing-box -n 20 --no-pager
    fi
}

# ===================== 状态显示 =====================
status_singbox() {
    [[ -n "$TERM" ]] && clear
    get_sysinfo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "系统:${blue}$release${plain}  内核:${blue}$version${plain}  处理器:${blue}$cpu${plain}  虚拟化:${blue}$vi${plain}  BBR算法:${blue}$bbr_val${plain}"
    echo -e "本地IPV4地址：${blue}$vps_ipv4${plain}  本地IPV6地址：${blue}$vps_ipv6${plain}"
    echo "------------------------------------------------------------------------------------"
    show_status
    echo "------------------------------------------------------------------------------------"
    echo ""
    blue "端口监听："
    if [[ -f "$CONFIG_FILE" ]]; then
        local rport hport tport
        rport=$(jq -r '.inbounds[0].listen_port // empty' "$CONFIG_FILE")
        hport=$(jq -r '.inbounds[1].listen_port // empty' "$CONFIG_FILE")
        tport=$(jq -r '.inbounds[2].listen_port // empty' "$CONFIG_FILE")
        echo -e "  VLESS Reality: ${blue}${rport:-未知}${plain}"
        echo -e "  Hysteria2:     ${blue}${hport:-未知}${plain}"
        echo -e "  TUIC:          ${blue}${tport:-未知}${plain}"
    else
        echo -e "  无配置文件"
    fi
    echo "------------------------------------------------------------------------------------"
}

# ===================== 查看配置信息 =====================
show_config() {
    [[ -n "$TERM" ]] && clear
    get_sysinfo
    logo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    blue "            Sing-box 配置信息"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        red "配置文件不存在: $CONFIG_FILE"
        return 1
    fi

    # 从 info.txt 读取保存的信息
    if [[ -f "$INFO_FILE" ]]; then
        source "$INFO_FILE"
        local port=$VLESS_PORT
        local uuid=$VLESS_UUID
        local pubkey=$VLESS_PUBKEY
        local shortid=$VLESS_SHORTID
        local hy2_port=$HY2_PORT
        local hy2_pass=$HY2_PASS
        local hy2_sha256=$HY2_SHA256
        local tuic_port=$TUIC_PORT
        local tuic_pass=$TUIC_PASS
        local server_ip=$SERVER_IP
    else
        # 如果 info.txt 不存在，从 config.json 提取
        yellow "配置信息文件不存在，从配置文件提取..."
        local port uuid priv_key pubkey shortid hy2_port hy2_pass hy2_sha256 tuic_port tuic_pass server_ip

        port=$(jq -r '.inbounds[0].listen_port // empty' "$CONFIG_FILE")
        hy2_port=$(jq -r '.inbounds[1].listen_port // empty' "$CONFIG_FILE")
        uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' "$CONFIG_FILE")
        shortid=$(jq -r '.inbounds[0].tls.reality.short_id[0] // empty' "$CONFIG_FILE")
        hy2_pass=$(jq -r '.inbounds[1].users[0].password // empty' "$CONFIG_FILE")
        tuic_port=$(jq -r '.inbounds[2].listen_port // empty' "$CONFIG_FILE")
        tuic_pass=$(jq -r '.inbounds[2].users[0].password // empty' "$CONFIG_FILE")
        priv_key=$(jq -r '.inbounds[0].tls.reality.private_key // empty' "$CONFIG_FILE")
        # PublicKey 从 .pubkey 文件提取（备份）
        pubkey=$(cat "$PUBKEY_FILE" 2>/dev/null || echo "")

        # 兼容旧版本：没有 pubkey 文件则标记
        if [[ -z "$pubkey" && -n "$priv_key" ]]; then
            pubkey="无法获取"
        fi

        # SHA256 从证书文件计算
        if [[ -f "$CONFIG_DIR/hy2.crt" ]]; then
            hy2_sha256=$(openssl x509 -in "$CONFIG_DIR/hy2.crt" -outform DER | sha256sum | awk '{print $1}')
        fi
        server_ip=$(curl -s --max-time 5 ipv4.icanhazip.com || curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 api.ip.sb)
    fi

    # 生成链接（仅当有完整信息时）
    if [[ -n "$port" && -n "$uuid" && -n "$pubkey" && -n "$shortid" && "$pubkey" != "无法获取" ]]; then
        local vless_url="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=gateway.icloud.com&fp=chrome&pbk=${pubkey}&sid=${shortid}&type=tcp&headerType=none#Reality"
    fi
    if [[ -n "$hy2_port" && -n "$hy2_pass" ]]; then
        local hy2_url="hysteria2://${hy2_pass}@${server_ip}:${hy2_port}?security=tls&alpn=h3&sni=bing.com&pinSHA256=${hy2_sha256}#Hysteria2"
    fi
    if [[ -n "$tuic_port" && -n "$tuic_pass" && -n "$uuid" ]]; then
        local tuic_url="tuic://${uuid}:${tuic_pass}@${server_ip}:${tuic_port}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=bing.com&insecure=1#Tuic"
    fi

    echo ""
    blue "VLESS Reality 节点："
    echo "  端口: ${port:-未知}"
    echo "  UUID: ${uuid:-未知}"
    echo "  SNI: gateway.icloud.com"
    echo "  PublicKey: ${pubkey:-未知}"
    echo "  ShortId: ${shortid:-未知}"
    if [[ -n "$vless_url" ]]; then
        echo "  链接:"
        green "  $vless_url"
    else
        yellow "  链接: 无法生成（缺少 PublicKey）"
    fi

    echo ""
    blue "Hysteria2 节点："
    echo "  端口: ${hy2_port:-未知}"
    echo "  密码: ${hy2_pass:-未知}"
    echo "  SNI: bing.com"
    echo "  pinSHA256: ${hy2_sha256:-未知}"
    if [[ -n "$hy2_url" ]]; then
        echo "  链接:"
        green "  $hy2_url"
    else
        yellow "  链接: 无法生成（缺少必要信息）"
    fi

    echo ""
    blue "TUIC 节点："
    echo "  端口: ${tuic_port:-未知}"
    echo "  UUID: ${uuid:-未知}"
    echo "  密码: ${tuic_pass:-未知}"
    echo "  SNI: bing.com"
    if [[ -n "$tuic_url" ]]; then
        echo "  链接:"
        green "  $tuic_url"
    else
        yellow "  链接: 无法生成（缺少必要信息）"
    fi

    echo ""
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    if [[ -f "$INFO_FILE" ]]; then
        blue "配置信息文件: $INFO_FILE"
    elif [[ -n "$pubkey" && "$pubkey" != "无法获取" ]]; then
        blue "配置信息: 从配置文件提取（部分字段）"
    else
        yellow "提示: 缺少配置信息文件，PublicKey 无法获取"
        yellow "建议: 重新安装以生成完整配置信息文件"
    fi
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

# ===================== 更新 =====================
update_singbox() {
    echo "检查更新..."
    local status
    status=$(check_installed)
    case "$status" in
        latest)
            green "已是最新版"
            return
            ;;
        not_installed)
            yellow "sing-box 未安装，执行安装..."
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
            green "更新完成"
            ;;
    esac
}

# ===================== 修复配置（从 PrivateKey 推导 PublicKey） =====================
fix_config() {
    if [[ $(id -u) -ne 0 ]]; then
        red "请使用 root 运行"
        return 1
    fi
    if [[ ! -f "$CONFIG_FILE" ]]; then
        red "配置文件不存在，无法修复"
        return 1
    fi

    # 检查是否已有 pubkey 且 info.txt 完整
    local existing_pubkey
    existing_pubkey=$(cat "$PUBKEY_FILE" 2>/dev/null || echo "")
    if [[ -n "$existing_pubkey" && -s "$INFO_FILE" && $(grep -c '^VLESS_SHORTID=' "$INFO_FILE" 2>/dev/null) -gt 0 && -n $(grep '^VLESS_SHORTID=' "$INFO_FILE" 2>/dev/null | cut -d= -f2) ]]; then
        green "配置信息完整，无需修复"
        return 0
    fi

    green "修复配置信息..."

    # 从 config.json 提取 PrivateKey（如果没有 pubkey 文件或 info.txt 不完整时也需要）
    local priv_key
    priv_key=$(jq -r '.inbounds[0].tls.reality.private_key // empty' "$CONFIG_FILE")
    if [[ -z "$priv_key" ]]; then
        red "配置文件中未找到 PrivateKey，无法修复"
        return 1
    fi

    yellow "从 PrivateKey 推导 PublicKey..."
    # 用 Python cryptography 库推导 X25519 公钥
    if ! command -v python3 &>/dev/null; then
        red "需要 python3 来推导 PublicKey，请安装 python3"
        return 1
    fi

    # 确保 cryptography 可用
    python3 -c "from cryptography.hazmat.primitives.asymmetric import x25519" 2>/dev/null || \
        apt install python3-cryptography -y 2>/dev/null || {
        red "无法安装 python3-cryptography，请手动安装后重试"
        return 1
    }

    local pub_key
    pub_key=$(python3 -c "
import base64, sys
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization

priv_b64url = '$priv_key'.strip()
# URL-safe base64 → 标准 base64（自动补 padding）
missing = len(priv_b64url) % 4
if missing:
    priv_b64url += '=' * (4 - missing)
try:
    priv_bytes = base64.urlsafe_b64decode(priv_b64url)
    if len(priv_bytes) != 32:
        sys.exit(1)
    priv = x25519.X25519PrivateKey.from_private_bytes(priv_bytes)
    pub = priv.public_key()
    pub_bytes = pub.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )
    pub_b64 = base64.b64encode(pub_bytes).decode()
    print(pub_b64)
except Exception:
    sys.exit(1)
" 2>/dev/null) || {
        red "PublicKey 推导失败"
        return 1
    }

    # 写入 config.json（jq 必须有）
    if ! command -v jq &>/dev/null; then
        apt install jq -y 2>/dev/null
    fi
    echo "$pub_key" > "$PUBKEY_FILE"
    green "PublicKey 已写入 $PUBKEY_FILE"

    # 重建 info.txt
    local port uuid shortid hy2_port hy2_pass hy2_sha256 tuic_port tuic_pass server_ip
    port=$(jq -r '.inbounds[0].listen_port' "$CONFIG_FILE")
    hy2_port=$(jq -r '.inbounds[1].listen_port // empty' "$CONFIG_FILE")
    uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' "$CONFIG_FILE")
    shortid=$(jq -r '.inbounds[0].tls.reality.short_id[0] // empty' "$CONFIG_FILE")
    hy2_pass=$(jq -r '.inbounds[1].users[0].password // empty' "$CONFIG_FILE")
    tuic_port=$(jq -r '.inbounds[2].listen_port // empty' "$CONFIG_FILE")
    tuic_pass=$(jq -r '.inbounds[2].users[0].password // empty' "$CONFIG_FILE")
    # SHA256 从证书文件计算
    if [[ -f "$CONFIG_DIR/hy2.crt" ]]; then
        hy2_sha256=$(openssl x509 -in "$CONFIG_DIR/hy2.crt" -outform DER | sha256sum | awk '{print $1}')
    fi
    server_ip=$(curl -s --max-time 5 ipv4.icanhazip.com || curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 api.ip.sb)

    cat > "$INFO_FILE" <<EOF
VLESS_PORT=$port
VLESS_UUID=$uuid
VLESS_PUBKEY=$pub_key
VLESS_SHORTID=$shortid
HY2_PORT=$hy2_port
HY2_PASS=$hy2_pass
HY2_SHA256=$hy2_sha256
TUIC_PORT=$tuic_port
TUIC_PASS=$tuic_pass
SERVER_IP=$server_ip
EOF
    green "配置信息已保存到: $INFO_FILE"
}

# ===================== 菜单 =====================
logo() {
    echo -e "${bblue} __    ____  _   _______   ______  ________ ${plain}"
    echo -e "${bblue}/ /   / __ \/ | / /__  /  / ____/ /  _/ __ \ ${plain}"
    echo -e "${bblue}/ /   / / / /  |/ /  / /  / __/    / // / / / ${plain}"
    echo -e "${bblue}/ /___/ /_/ / /|  /  / /__/ /____ _/ // /_/ / ${plain}"
    echo -e "${bblue}\____/\____/_/ |_/  /____/_____(_)___/\____/  ${plain}"
}

show_menu() {
    [[ -n "$TERM" ]] && clear
    get_sysinfo
    logo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "${bblue}Sing-box一键安装hysteria2+VLESS Reality管理脚本${plain}"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    white "项目:github.com/makessr/sing-box-installer"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green " 1. 一键安装 sing-box"
    green " 2. 卸载 sing-box"
    echo "----------------------------------------------------------------------------------"
    green " 3. 重启 sing-box"
    green " 4. 查看运行状态"
    green " 5. 更新 sing-box"
    green " 6. 查看配置信息（缺少时自动修复）"
    echo "----------------------------------------------------------------------------------"
    green " 0. 退出脚本"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "系统:${blue}$release${plain}  内核:${blue}$version${plain}  处理器:${blue}$cpu${plain}  虚拟化:${blue}$vi${plain}  BBR算法:${blue}$bbr_val${plain}"
    echo -e "本地IPV4地址：${blue}$vps_ipv4${plain}  本地IPV6地址：${blue}$vps_ipv6${plain}"
    echo "------------------------------------------------------------------------------------"
    show_status
    echo "------------------------------------------------------------------------------------"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    readp "请输入数字【0-6】:" Input
    case "$Input" in
        1) check_uninstall && install_singbox;;
        2) check_install && uninstall_singbox;;
        3) check_install && restart_singbox;;
        4) check_install && status_singbox && back;;
        5) check_install && update_singbox;;
        6) check_install && fix_config && show_config && back;;
        *) exit;;
    esac
    show_menu
}

# ===================== 返回菜单 =====================
back() {
    white "------------------------------------------------------------------------------------"
    white " 回主菜单，请按任意键"
    white " 退出脚本，请按Ctrl+C"
    get_char && show_menu
}

get_char() {
    SAVEDSTTY=$(stty -g)
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2>/dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

# ===================== 命令分发 =====================
case "$1" in
    install)
        install_singbox "$2"
        ;;
    uninstall)
        uninstall_singbox
        ;;
    restart)
        check_install && restart_singbox
        ;;
    status)
        check_install && status_singbox
        ;;
    update)
        check_install && update_singbox "$2"
        ;;
    config)
        check_install && fix_config && show_config
        ;;
    fix)
        check_install && fix_config && show_config
        ;;
    *)
        show_menu
        ;;
esac
