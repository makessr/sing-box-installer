# Sing-box 一键安装脚本

一键安装 VLESS Reality + Hysteria2 双协议代理。

## 使用方式

```bash
curl -sS -O https://raw.githubusercontent.com/makessr/sing-box-installer/main/reality.sh
chmod +x reality.sh
```

### 安装

```bash
bash reality.sh install          # 随机端口
bash reality.sh install 12345    # 指定端口
```

首次安装会自动完成：启用 BBR → 下载 sing-box → 生成配置和自签证书 → 启动服务 → 输出连接链接。

### 其他命令

| 命令 | 说明 |
|------|------|
| `bash reality.sh status` | 查看服务状态、版本、监听端口 |
| `bash reality.sh restart` | 重启服务 |
| `bash reality.sh update` | 仅更新二进制到最新版 + 重启（不改配置） |
| `bash reality.sh uninstall` | 卸载（删二进制、配置、服务） |

## 特性

- **幂等** — BBR 已启用则跳过，sing-box 已最新则跳过下载
- **端口冲突检测** — 随机端口自动避开已占用端口
- **旧配置自动备份** — 重装时保留 `.bak.` 后缀备份
- **支持 arm64 / amd64**

## 输出示例

安装完成后会输出 VLESS Reality 和 Hysteria2 的连接链接，可直接导入 v2rayN / Shadowrocket / sing-box 等客户端。

```
VLESS Reality:
  端口: 46858
  SNI: gateway.icloud.com
  链接:
  vless://xxx@1.2.3.4:46858?..."

Hysteria2:
  端口: 46859
  SNI: bing.com
  密码: xxx
  链接:
  hysteria2://xxx@1.2.3.4:46859?...
```

## 说明

- VLESS Reality 不需要证书，直接可用
- Hysteria2 使用内置自签证书（客户端需 `insecure=1`）
- 首次安装后如需修改端口，重新执行 `install` 即可
