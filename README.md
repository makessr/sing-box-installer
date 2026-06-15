# reality.sh — sing-box 一键安装脚本（VLESS+Reality + Hysteria2）

## 简介

在 Linux 服务器上一键部署 sing-box，同时开启 **VLESS+Reality** 和 **Hysteria2** 两个协议，自动生成连接信息。

## 快速安装

```bash
# 默认随机端口
bash <(curl -fsSL https://raw.githubusercontent.com/makessr/one-times/main/reality.sh) install

# 指定 VLESS 端口（Hysteria2 端口自动 +1）
bash <(curl -fsSL https://raw.githubusercontent.com/makessr/one-times/main/reality.sh) install 34567
```

执行后输出示例：

```
==============================
✅ Sing-box 安装完成

VLESS Reality:
  端口: 34567
  SNI: gateway.icloud.com
  链接:
  vless://xxx@IP:34567?...

Hysteria2:
  端口: 34568
  SNI: bing.com
  密码: xxxxxx
  链接:
  hysteria2://xxxx@IP:34568?...
==============================
```

## 其他命令

| 命令 | 说明 |
|---|---|
| `install [端口]` | 安装（不指定端口则随机生成） |
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

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/makessr/one-times/main/reality.sh) uninstall
```

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
