# reality.sh — sing-box 一键安装脚本（VLESS+Reality + Hysteria2）

## 简介

在 Linux 服务器上一键部署 sing-box，同时开启 **VLESS+Reality** 和 **Hysteria2** 两个协议，自动生成连接信息。

## 快速安装 / 卸载

```bash
# 安装（端口随机 30000-50000）
bash <(curl -fsSL https://raw.githubusercontent.com/makessr/sing-box-installer/main/reality.sh) install

# 卸载
bash <(curl -fsSL https://raw.githubusercontent.com/makessr/sing-box-installer/main/reality.sh) uninstall
```

执行后输出（脚本终端输出）：

```
==============================
✅ Sing-box 安装完成

VLESS Reality:
  端口: 34567
  SNI: gateway.icloud.com
  链接:
  vless://4e1a7b2c-8f3d-4a5e-9b6c-1d2e3f4a5b6c@1.2.3.4:34567?encryption=none&flow=xtls-rprx-vision&security=reality&sni=gateway.icloud.com&fp=ios&pbk=xxxxx&sid=abcd1234&type=tcp#Reality

Hysteria2:
  端口: 34568
  SNI: bing.com
  密码: abc123xyz
  链接:
  hysteria2://abc123xyz@1.2.3.4:34568?sni=bing.com&insecure=0&alpn=h3#Hysteria2
==============================
```

## 客户端配置

### v2rayN / v2rayNG

直接复制上方的 **VLESS 链接** 和 **Hysteria2 链接**，在客户端中导入即可。

### sing-box 配置片段

在现有 sing-box 配置的 `inbounds` 中添加：

```json
{
  "type": "vless",
  "listen": "::",
  "listen_port": 34567,
  "users": [
    { "uuid": "4e1a7b2c-8f3d-4a5e-9b6c-1d2e3f4a5b6c", "flow": "xtls-rprx-vision" }
  ],
  "tls": {
    "enabled": true,
    "server_name": "gateway.icloud.com",
    "reality": {
      "enabled": true,
      "handshake": { "server": "gateway.icloud.com", "server_port": 443 },
      "private_key": "xxxxx",
      "short_id": ["abcd1234"]
    }
  }
}
```

```json
{
  "type": "hysteria2",
  "listen": "::",
  "listen_port": 34568,
  "users": [
    { "password": "abc123xyz" }
  ],
  "tls": {
    "enabled": true,
    "server_name": "bing.com",
    "alpn": ["h3"]
  }
}
```

### Clash Meta / mihomo 配置片段

在 `proxies` 中添加：

```yaml
- name: "Reality"
  type: vless
  server: 1.2.3.4
  port: 34567
  uuid: 4e1a7b2c-8f3d-4a5e-9b6c-1d2e3f4a5b6c
  flow: xtls-rprx-vision
  tls: true
  servername: gateway.icloud.com
  reality:
    public-key: xxxxx
    short-id: abcd1234
  client-fingerprint: ios

- name: "Hysteria2"
  type: hysteria2
  server: 1.2.3.4
  port: 34568
  password: abc123xyz
  sni: bing.com
  alpn:
    - h3
  skip-cert-verify: false
```

## 其他命令

| 命令 | 说明 |
|---|---|
| `install [端口]` | 安装（不指定端口则随机生成（30000-50000）） |
| `uninstall` | 卸载并清理 sing-box |
| `restart` | 重启服务 |
| `status` | 查看运行状态 |

## 前置要求

- **操作系统**: Ubuntu / Debian（root 权限）
- **架构**: x86_64 / aarch64 / armv7

## 特性

- 自动开启 **BBR** 拥塞控制
- **VLESS+Reality** 使用 `gateway.icloud.com` 作为 SNI
- **Hysteria2** 使用 `bing.com` 作为 SNI，基于 QUIC 传输
- 自动检测公网 IP（多备用源）
- 注册为 systemd 服务，开机自启

## 更新记录

### 2026-06-15 v2.0

- 新增 Hysteria2 协议支持，与 VLESS+Reality 并存
- SNI 分开配置：VLESS 使用 `gateway.icloud.com`，Hysteria2 使用 `bing.com`
- 优化密钥解析方式，提升兼容性
- 公网 IP 检测增加备用源，避免超时失败
- sysctl 报错信息可见，便于排查
- Hysteria2 握手端口可配置

### 2025-03-01 v1.0

- 初始版本，支持 VLESS+Reality 一键部署
