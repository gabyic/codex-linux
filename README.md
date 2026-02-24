# Codex for Linux

在 Linux 服务器上登录 ChatGPT Codex，自动安装 Codex CLI 并完成 OAuth 授权。

零依赖，仅需 `curl` + `openssl`（Linux 自带）。

## 解决什么问题

Codex CLI 官方登录需要本地浏览器弹窗授权，Linux 服务器没有图形界面无法完成。本工具通过「复制 URL → 浏览器登录 → 粘贴回调 URL」的方式，让你在任何 Linux 服务器上完成 Codex 登录。

## 安装

```bash
curl -O https://raw.githubusercontent.com/gabyic/codex-linux/main/codex-login.sh
chmod +x codex-login.sh
```

全局安装：

```bash
sudo curl -o /usr/local/bin/codex-login https://raw.githubusercontent.com/gabyic/codex-linux/main/codex-login.sh
sudo chmod +x /usr/local/bin/codex-login
```

## 使用

### 登录

```bash
./codex-login.sh login
```

脚本会自动：
1. 检测 Codex CLI，未安装则自动安装（通过 npm）
2. 生成 OAuth 授权 URL
3. 你复制 URL 到本地浏览器打开，登录 ChatGPT
4. 登录后浏览器跳转到一个打不开的页面（正常现象）
5. 复制浏览器地址栏的完整 URL，粘贴回终端
6. Token 自动保存到 `~/.codex/auth.json`（Codex CLI 原生格式）
7. 直接运行 `codex` 即可使用

### 查看状态

```bash
./codex-login.sh status
```

### 刷新 Token

```bash
./codex-login.sh refresh
```

### 获取 Token

```bash
./codex-login.sh token
```

## 原理

使用 OpenAI 官方的 OAuth PKCE 流程（与 Codex CLI 相同的 client_id），通过浏览器授权获取 access_token 和 refresh_token。Token 直接写入 `~/.codex/auth.json`，Codex CLI 无缝使用。

## 要求

- Linux / macOS
- curl, openssl, base64（系统自带）
- Node.js + npm（Codex CLI 安装需要，脚本会自动安装）

## License

MIT
