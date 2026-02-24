# Codex for Linux

[中文](#中文) | [English](#english)

---

## 中文

在 Linux 服务器上登录 ChatGPT Codex，自动安装 Codex CLI 并完成 OAuth 授权。

零依赖，仅需 `curl` + `openssl`（Linux 自带）。

### 解决什么问题

Codex CLI 官方登录需要本地浏览器弹窗授权，Linux 服务器没有图形界面无法完成。本工具通过「复制 URL → 浏览器登录 → 粘贴回调 URL」的方式，让你在任何 Linux 服务器上完成 Codex 登录。

### 安装

```bash
curl -O https://raw.githubusercontent.com/gabyic/codex-linux/main/codex-login.sh
chmod +x codex-login.sh
```

全局安装：

```bash
sudo curl -o /usr/local/bin/codex-login https://raw.githubusercontent.com/gabyic/codex-linux/main/codex-login.sh
sudo chmod +x /usr/local/bin/codex-login
```

### 使用

#### 登录

```bash
./codex-login.sh login

# 全局安装后
codex-login login
```

脚本会自动：
1. 检测 Node.js / npm，未安装则自动安装
2. 检测 Codex CLI，未安装则通过 npm 自动安装
3. 生成 OAuth 授权 URL
4. 你复制 URL 到本地浏览器打开，登录 ChatGPT
5. 登录后浏览器跳转到一个打不开的页面（正常现象）
6. 复制浏览器地址栏的完整 URL，粘贴回终端
7. Token 自动保存到 `~/.codex/auth.json`（Codex CLI 原生格式）
8. 直接运行 `codex` 即可使用

#### 查看状态

```bash
./codex-login.sh status
codex-login status        # 全局安装
```

#### 刷新 Token

```bash
./codex-login.sh refresh
codex-login refresh       # 全局安装
```

#### 获取 Token

```bash
./codex-login.sh token
codex-login token         # 全局安装
```

### 原理

使用 OpenAI 官方的 OAuth PKCE 流程（与 Codex CLI 相同的 client_id），通过浏览器授权获取 access_token 和 refresh_token。Token 直接写入 `~/.codex/auth.json`，Codex CLI 无缝使用。

### 要求

- Linux / macOS
- curl, openssl, base64（系统自带）
- Node.js + npm（Codex CLI 安装需要，脚本会自动安装）

---

## English

Login to ChatGPT Codex on Linux servers. Auto-installs Codex CLI and completes OAuth authorization.

Zero dependencies — only `curl` + `openssl` (pre-installed on Linux).

### Problem

Codex CLI requires a local browser popup for OAuth login, which doesn't work on headless Linux servers. This tool uses a "copy URL → browser login → paste callback URL" flow, enabling Codex login on any Linux server.

### Install

```bash
curl -O https://raw.githubusercontent.com/gabyic/codex-linux/main/codex-login.sh
chmod +x codex-login.sh
```

Global install:

```bash
sudo curl -o /usr/local/bin/codex-login https://raw.githubusercontent.com/gabyic/codex-linux/main/codex-login.sh
sudo chmod +x /usr/local/bin/codex-login
```

### Usage

#### Login

```bash
./codex-login.sh login

# After global install
codex-login login
```

The script will automatically:
1. Detect Node.js / npm, install if missing
2. Detect Codex CLI, install via npm if missing
3. Generate an OAuth authorization URL
4. You copy the URL to your local browser and sign in to ChatGPT
5. After login, the browser redirects to a page that won't load (this is expected)
6. Copy the full URL from the browser address bar and paste it back into the terminal
7. Token is saved to `~/.codex/auth.json` (native Codex CLI format)
8. Run `codex` directly — it just works

#### Status

```bash
./codex-login.sh status
codex-login status        # global install
```

#### Refresh Token

```bash
./codex-login.sh refresh
codex-login refresh       # global install
```

#### Get Token

```bash
./codex-login.sh token
codex-login token         # global install
```

### How It Works

Uses OpenAI's official OAuth PKCE flow (same client_id as Codex CLI) to obtain access_token and refresh_token via browser authorization. Tokens are written directly to `~/.codex/auth.json`, so Codex CLI works seamlessly.

### Requirements

- Linux / macOS
- curl, openssl, base64 (pre-installed)
- Node.js + npm (needed for Codex CLI, auto-installed by the script)

## License

MIT
