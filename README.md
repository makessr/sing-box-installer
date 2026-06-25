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

```bash
bash reality.sh
```

| 编号 | 功能 |
|------|------|
| 1 | 一键安装 sing-box |
| 2 | 卸载 sing-box |
| 3 | 重启 sing-box |
| 4 | 查看运行状态 |
| 5 | 更新 sing-box |
| 6 | 查看配置信息（缺失时自动修复 PublicKey） |
| 0 | 退出 |

### 命令行模式

```bash
bash reality.sh install            # 随机端口安装
bash reality.sh install 12345      # 指定端口安装
bash reality.sh status             # 查看状态
bash reality.sh config             # 查看配置信息
bash reality.sh restart            # 重启服务
bash reality.sh update             # 更新二进制
bash reality.sh fix                # 修复缺失的配置信息
bash reality.sh uninstall          # 卸载
```

## 工作流程

1. **安装** → 自动：启用 BBR → 下载 sing-box → 生成 VLESS Reality + Hysteria2 配置 → 启动服务
2. **日常** → 菜单中查看状态、重启、更新
3. **配置丢失** → 选 `6` 查看，PublicKey 或 info.txt 缺失时自动修复

## 功能特性

- ✅ **幂等安装** — BBR 已启用则跳过，sing-box 已最新则跳过下载
- ✅ **端口冲突检测** — 随机端口自动避开已占用端口
- ✅ **旧配置自动备份** — 重装时保留 `.bak.` 后缀备份
- ✅ **配置信息持久化** — `info.txt` + `config.json` 双备份，PublicKey 嵌入 JSON
- ✅ **PublicKey 修复** — 旧版或 `info.txt` 丢失时，从 PrivateKey 自动推导 PublicKey
- ✅ **彩色交互菜单** — LONZE.IO ASCII logo + 实时系统信息面板
- ✅ **`jq` 解析配置** — 所有 JSON 解析用 `jq`，支持多行字段
- ✅ 支持 **arm64 / amd64 / armv7**
- ✅ 静默模式：传参直接执行，无需交互

## 输出示例

```text
VLESS Reality 节点：
  端口: 36903
  UUID: b0ddd162-3648-4e7a-845b-d2af7c7c710b
  SNI: gateway.icloud.com
  PublicKey: 9+TnZWyqa5PnVtLq08tNndiY8wxIdEp76P2yDnLrGUE=
  ShortId: cd83310a
  链接:
  vless://b0ddd162-...@1.2.3.4:36903?encryption=none&flow=xtls-rprx-vision&security=reality&sni=gateway.icloud.com&fp=ios&pbk=...&sid=cd83310a&type=tcp#Reality

Hysteria2 节点：
  端口: 36904
  密码: d3m+mB9s8nfLMwUh5DeY9A==
  SNI: bing.com
  链接:
  hysteria2://d3m+mB9s8nfLMwUh5DeY9A==@1.2.3.4:36904?sni=bing.com&insecure=1&alpn=h3#Hysteria2
```

系统状态面板：

```text
系统:Debian  内核:6.1.0  处理器:amd64  虚拟化:kvm  BBR算法:bbr
本地IPV4地址：1.2.3.4  本地IPV6地址：无IPV6
sing-box 状态: 已运行  sing-box 自启: 是
sing-box 版本: 1.13.13
```

## 配置存储

| 文件 | 说明 |
|------|------|
| `/etc/sing-box/config.json` | sing-box 主配置文件（含 `_pubkey` 备用字段） |
| `/etc/sing-box/info.txt` | 节点连接信息（环境变量格式，供菜单读取） |
| `/etc/sing-box/hy2.key` | Hysteria2 自签证书私钥 |
| `/etc/sing-box/hy2.crt` | Hysteria2 自签证书 |

## 常见问题

**Q: PublicKey 显示"无法获取"？**
A: 选菜单 `6` 查看配置时会自动修复，或运行 `bash reality.sh fix` 手动修复。

**Q: `info.txt` 误删了？**
A: 同样运行 `bash reality.sh fix`，会自动重建。

**Q: 想改端口？**
A: 重新运行 `bash reality.sh install [新端口]`，旧配置会自动备份为 `.bak.` 文件。

**Q: Hysteria2 客户端连不上？**
A: 客户端需设置 `insecure=1`（跳过自签证书验证）和 `alpn=h3`。

**Q: 安装后没看到 PublicKey？**
A: 旧版安装的 `config.json` 没有 `_pubkey` 字段，运行 `fix` 即可补全。

## 说明

- VLESS Reality 不需要证书，直接可用
- Hysteria2 使用内置自签证书，客户端需 `insecure=1`
- 首次安装后如需修改端口，重新执行 `install` 即可
- 配置信息保存在 `/etc/sing-box/info.txt`，也可通过 `config` 命令或菜单查看
- 修复功能不会改变现有密钥，仅补全缺失的 PublicKey 和 info.txt
