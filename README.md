# Sing-box 一键安装脚本

一键安装 **VLESS Reality + Hysteria2** 双协议代理，带交互式管理菜单。

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
| 0 | 退出 |

### 命令行模式

```bash
bash reality.sh install          # 随机端口安装
bash reality.sh install 12345    # 指定端口安装
bash reality.sh status           # 查看状态
bash reality.sh restart          # 重启服务
bash reality.sh update           # 更新二进制
bash reality.sh uninstall        # 卸载
```

## 功能特性

- ✅ **幂等安装** — BBR 已启用则跳过，sing-box 已最新则跳过下载
- ✅ **端口冲突检测** — 随机端口自动避开已占用端口
- ✅ **旧配置自动备份** — 重装时保留 `.bak.` 后缀备份
- ✅ **彩色交互菜单** — LONZE.IO ASCII logo + 系统状态面板
- ✅ **系统信息面板** — 显示 OS/内核/架构/虚拟化/BBR/IP
- ✅ 支持 **arm64 / amd64 / armv7**
- ✅ 静默模式：传参直接执行，无需交互

## 输出示例

安装完成后输出两条分享链接，可直接导入 v2rayN / Shadowrocket / sing-box 等客户端：

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
```

安装后自动显示系统状态面板：

```text
系统:Debian  内核:6.1.0  处理器:amd64  虚拟化:kvm  BBR算法:bbr
本地IPV4地址：1.2.3.4  本地IPV6地址：无IPV6
sing-box 状态: 已运行  sing-box 自启: 是
sing-box 版本: 1.13.13
```

## 说明

- VLESS Reality 不需要证书，直接可用
- Hysteria2 使用内置自签证书（客户端需 `insecure=1`）
- 首次安装后如需修改端口，重新执行 `install` 即可
- 原 `reality.sh` 命令行参数完全兼容
