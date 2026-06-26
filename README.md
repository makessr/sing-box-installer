# Sing-box 一键安装脚本

一键安装 **VLESS Reality + Hysteria2 + TUIC v5** 三协议代理，带交互式管理菜单。

```
 __    ____  _   _______   ______  ________ 
/ /   / __ \/ | / /__  /  / ____/ /  _/ __ \
/ /   / / / /  |/ /  / /  / __/    / // / / /
/ /___/ /_/ / /|  /  / /__/ /____ _/ // /_/ / 
\____/\____/_/ |_/  /____/_____(_)___/\____/  
```

## 使用方式

```bash
curl -sS -O https://raw.githubusercontent.com/makessr/sing-box-installer/main/reality.sh
chmod +x reality.sh
```

### 交互菜单（推荐）

直接运行进入彩色的交互菜单：

```bash
bash reality.sh
```

菜单选项：

| 编号 | 功能 |
|------|------|
| 1 | 一键安装 sing-box |
| 2 | 卸载 sing-box |
| 3 | 重启 sing-box |
| 4 | 查看运行状态 |
| 5 | 更新 sing-box |
| 6 | 查看配置信息（缺少时自动修复） |
| 0 | 退出 |

### 命令行模式

```bash
bash reality.sh install          # 随机端口安装
bash reality.sh install 12345    # 指定端口安装
bash reality.sh status           # 查看运行状态
bash reality.sh config           # 查看配置信息（含自动修复）
bash reality.sh fix              # 修复配置信息并查看
bash reality.sh restart          # 重启服务
bash reality.sh update           # 更新二进制
bash reality.sh uninstall        # 卸载
```

## 功能特性

- ✅ **三协议** — VLESS Reality + Hysteria2 + TUIC v5
- ✅ **幂等安装** — BBR 已启用则跳过，sing-box 已最新则跳过下载
- ✅ **端口冲突检测** — 随机端口自动避开已占用端口（同时检测连续 3 个端口）
- ✅ **旧配置自动备份** — 重装时保留 `.bak.YYYYMMDD_HHMMSS` 后缀备份
- ✅ **配置信息保存** — 安装时自动保存配置到 `/etc/sing-box/info.txt` 和 `/etc/sing-box/.pubkey`
- ✅ **配置信息查看** — 随时查看已安装的节点配置和分享链接
- ✅ **配置自动修复** — 缺少 PublicKey 或 info.txt 时，自动从 PrivateKey 推导并重建
- ✅ **Hysteria2 证书 pin** — 自动计算并保存 SHA256，支持客户端证书校验
- ✅ **防火墙** — 自动放行 iptables 规则并持久化
- ✅ **彩色交互菜单** — ASCII logo + 系统状态面板
- ✅ **系统信息面板** — 显示 OS / 内核 / 架构 / 虚拟化 / BBR / IP
- ✅ 支持 **arm64 / amd64 / armv7**
- ✅ 支持 **Ubuntu / Debian / CentOS**
- ✅ 静默模式：传参直接执行，无需交互

## 输出示例

安装完成后输出三条分享链接，可直接导入 v2rayN / Shadowrocket / sing-box / v2rayNG 等客户端：

```text
VLESS Reality 节点：
  端口: 46858
  UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  SNI: gateway.icloud.com
  PublicKey: xxxxxxxxxxxxxxxxxxxx
  ShortId: xxxx
  链接:
  vless://xxx@1.2.3.4:46858?...

Hysteria2 节点：
  端口: 46859
  密码: xxxxxxxxxxxxxxxx
  SNI: bing.com
  链接:
  hysteria2://xxx@1.2.3.4:46859?...

TUIC 节点：
  端口: 46860
  UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  密码: xxxxxxxxxxxxxxxx
  SNI: bing.com
  链接:
  tuic://xxx@1.2.3.4:46860?...
```

安装后自动显示系统状态面板：

```text
系统:Debian  内核:6.1.0  处理器:amd64  虚拟化:kvm  BBR算法:bbr
本地IPV4地址：1.2.3.4  本地IPV6地址：无IPV6
sing-box 状态: 已运行  sing-box 自启: 是
sing-box 版本: 1.13.13
```

## 端口分配

安装时自动分配连续 3 个端口：

| 协议 | 端口偏移 | 传输层 |
|------|----------|--------|
| VLESS Reality | 指定端口 | TCP |
| Hysteria2 | 端口 + 1 | UDP |
| TUIC v5 | 端口 + 2 | UDP |

## 配置文件路径

| 文件 | 路径 | 说明 |
|------|------|------|
| 主配置 | `/etc/sing-box/config.json` | sing-box 运行时配置 |
| 配置信息 | `/etc/sing-box/info.txt` | 安装时的完整配置信息 |
| PublicKey | `/etc/sing-box/.pubkey` | VLESS Reality 公钥备份 |
| 自签证书 | `/etc/sing-box/hy2.crt` | Hysteria2 / TUIC TLS 证书 |
| 证书密钥 | `/etc/sing-box/hy2.key` | Hysteria2 / TUIC TLS 私钥 |
| 服务文件 | `/etc/systemd/system/sing-box.service` | systemd 服务定义 |
| 二进制 | `/usr/local/bin/sing-box` | sing-box 可执行文件 |

## 说明

- VLESS Reality 不需要证书，直接可用
- Hysteria2 和 TUIC 使用内置自签证书（客户端需 `insecure=1`，或使用 `pinSHA256` 校验）
- 首次安装后如需修改端口，重新执行 `install` 即可
- 安装后配置信息保存在 `/etc/sing-box/info.txt`，可通过菜单或命令查看
- 如忘记配置信息，运行 `bash reality.sh config` 或选择菜单选项 `6` 查看
- 如缺少 PublicKey 或 info.txt 丢失，`config` 命令会自动推导并修复
- 原 `reality.sh` 命令行参数完全兼容