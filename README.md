# Codex for Linux

在 Linux 服务器上登录 ChatGPT Codex，获取 API access_token。

零依赖，仅需 `curl` + `openssl`（Linux 自带）。

## 安装

```bash
curl -O https://raw.githubusercontent.com/gabyic/codex-linux/main/codex-login.sh
chmod +x codex-login.sh
```

或者全局安装：

```bash
sudo curl -o /usr/local/bin/codex-login https://raw.githubusercontent.com/gabyic/codex-linux/main/codex-login.sh
sudo chmod +x /usr/local/bin/codex-login
```

## 使用

### 登录

```bash
./codex-login.sh login
```

1. 脚本会生成一个授权 URL
2. 复制 URL 到本地浏览器打开，登录 ChatGPT
3. 登录后浏览器会跳转到一个打不开的页面（正常现象）
4. 复制浏览器地址栏的完整 URL，粘贴回终端
5. Token 自动保存到 `~/.codex-token.json`

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
# 直接输出 access_token
./codex-login.sh token

# 配合 curl 使用
curl -H "Authorization: Bearer $(./codex-login.sh token)" \
  https://chatgpt.com/backend-api/codex/responses \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.2-codex","input":[{"role":"user","content":"hello"}],"stream":false}'
```

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CODEX_TOKEN_FILE` | Token 保存路径 | `~/.codex-token.json` |

## 原理

使用 OpenAI 官方的 OAuth PKCE 流程（与 Codex CLI 相同的 client_id），通过浏览器授权获取 access_token 和 refresh_token。Token 过期后可自动刷新。

## 要求

- Linux / macOS
- curl
- openssl
- base64（coreutils）

## License

MIT
