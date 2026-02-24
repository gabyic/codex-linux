#!/usr/bin/env bash
# codex-login.sh — ChatGPT Codex OAuth 登录工具 (Linux)
# 零依赖：仅需 curl, openssl, base64
# https://github.com/gabyic/codex-linux

set -euo pipefail

# ── 常量 ──────────────────────────────────────────────
CLIENT_ID="app_EMoamEEZ73f0CkXaXp7hrann"
AUTHORIZE_URL="https://auth.openai.com/oauth/authorize"
TOKEN_URL="https://auth.openai.com/oauth/token"
REDIRECT_URI="http://localhost:1455/auth/callback"
SCOPE="openid profile email offline_access"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_AUTH_FILE="${CODEX_HOME}/auth.json"

# ── 颜色 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── 工具函数 ──────────────────────────────────────────
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
bold()  { echo -e "${BOLD}$*${NC}"; }

check_deps() {
    local missing=()
    for cmd in curl openssl base64; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "缺少依赖: ${missing[*]}"
        echo "  请安装: sudo apt install -y curl openssl coreutils"
        exit 1
    fi
}

# URL 安全的 base64 编码（去掉 = 填充，替换 +/ 为 -_）
base64url_encode() {
    if base64 -w0 </dev/null &>/dev/null; then
        base64 -w0 | tr '+/' '-_' | tr -d '='
    else
        base64 | tr -d '\n' | tr '+/' '-_' | tr -d '='
    fi
}

# 生成随机字符串
random_string() {
    openssl rand -base64 "$1" | base64url_encode
}

# URL 编码
urlencode() {
    local string="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('$string', safe=''))" 2>/dev/null \
        || printf '%s' "$string" | curl -Gso /dev/null -w '%{url_effective}' --data-urlencode @- '' | cut -c3-
}

# 从 JSON 中提取字段（不依赖 jq）
json_get() {
    local json="$1" key="$2"
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$key // empty"
        return
    fi
    if command -v python3 &>/dev/null; then
        python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('$key',''))" <<< "$json"
        return
    fi
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*"'$key'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

json_get_num() {
    local json="$1" key="$2"
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$key // 0"
        return
    fi
    if command -v python3 &>/dev/null; then
        python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('$key',0))" <<< "$json"
        return
    fi
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9]*" | head -1 | grep -o '[0-9]*$'
}

# 从嵌套 JSON 中提取字段（支持 tokens.access_token 这样的路径）
json_get_nested() {
    local json="$1" path="$2"
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$path // empty"
        return
    fi
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
keys = '$path'.split('.')
for k in keys:
    if isinstance(d, dict):
        d = d.get(k, '')
    else:
        d = ''
        break
print(d if d else '')
" <<< "$json"
        return
    fi
    # 简单的 fallback，只支持一层嵌套
    echo "$json" | grep -o "\"${path##*.}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*"'${path##*.}'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

# 解码 JWT 并提取 account_id
extract_account_id() {
    local token="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, base64, sys
try:
    parts = '$token'.split('.')
    if len(parts) != 3:
        sys.exit(1)
    payload = parts[1]
    # 添加必要的填充
    padding = len(payload) % 4
    if padding:
        payload += '=' * (4 - padding)
    decoded = base64.urlsafe_b64decode(payload).decode('utf-8')
    data = json.loads(decoded)
    account_id = data.get('https://api.openai.com/auth', {}).get('chatgpt_account_id', '')
    print(account_id)
except:
    pass
"
    else
        # Fallback: 使用 openssl 和 sed
        local payload=$(echo "$token" | cut -d. -f2)
        # 添加 base64 填充
        local padding=$((4 - ${#payload} % 4))
        [[ $padding -ne 4 ]] && payload="${payload}$(printf '=%.0s' $(seq 1 $padding))"
        # 解码并提取 account_id
        echo "$payload" | base64 -d 2>/dev/null | grep -o '"chatgpt_account_id":"[^"]*"' | cut -d'"' -f4
    fi
}

json_get_num() {
    local json="$1" key="$2"
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$key // 0"
        return
    fi
    if command -v python3 &>/dev/null; then
        python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('$key',0))" <<< "$json"
        return
    fi
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9]*" | head -1 | grep -o '[0-9]*$'
}

# 解码 JWT 并提取 account_id
ensure_codex_cli() {
    if command -v codex &>/dev/null; then
        local version
        version=$(codex --version 2>/dev/null || echo "unknown")
        info "Codex CLI 已安装 (${version})"
        return 0
    fi

    warn "未检测到 Codex CLI"

    # 检查 npm
    if ! command -v npm &>/dev/null; then
        # 检查 node
        if ! command -v node &>/dev/null; then
            warn "未检测到 Node.js，正在安装..."
            if command -v apt &>/dev/null; then
                curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt install -y nodejs
            elif command -v yum &>/dev/null; then
                curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - && sudo yum install -y nodejs
            else
                error "无法自动安装 Node.js，请手动安装后重试"
                echo "  https://nodejs.org/en/download/"
                exit 1
            fi
        fi
    fi

    info "正在安装 Codex CLI..."
    npm install -g @openai/codex 2>&1 | tail -3

    if command -v codex &>/dev/null; then
        info "Codex CLI 安装成功"
    else
        error "Codex CLI 安装失败，请手动安装: npm install -g @openai/codex"
        exit 1
    fi
}

# ── PKCE ──────────────────────────────────────────────
generate_pkce() {
    CODE_VERIFIER=$(random_string 64)
    CODE_CHALLENGE=$(printf '%s' "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64url_encode)
}

# ── 登录 ──────────────────────────────────────────────
do_login() {
    check_deps

    echo ""
    bold "╔══════════════════════════════════════════╗"
    bold "║     Codex for Linux — OAuth 登录工具     ║"
    bold "╚══════════════════════════════════════════╝"
    echo ""

    # 0. 检测并安装 Codex CLI
    ensure_codex_cli
    echo ""

    # 1. 生成 PKCE
    generate_pkce
    STATE=$(random_string 32)

    # 2. 构建授权 URL
    AUTH_URL="${AUTHORIZE_URL}?response_type=code&client_id=${CLIENT_ID}&redirect_uri=$(urlencode "$REDIRECT_URI")&scope=$(urlencode "$SCOPE")&state=${STATE}&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256&id_token_add_organizations=true&codex_cli_simplified_flow=true"

    info "授权 URL 已生成"
    echo ""
    bold "步骤 1: 复制下面的 URL 到浏览器打开并登录 ChatGPT"
    echo ""
    echo -e "${CYAN}${AUTH_URL}${NC}"
    echo ""
    bold "步骤 2: 登录后浏览器会跳转到一个打不开的页面，这是正常的"
    bold "        复制浏览器地址栏中的完整 URL 粘贴到下面"
    echo ""
    read -rp "$(echo -e "${YELLOW}粘贴回调 URL: ${NC}")" CALLBACK_URL

    if [[ -z "$CALLBACK_URL" ]]; then
        error "未输入回调 URL"
        exit 1
    fi

    # 3. 解析 code 和 state
    CALLBACK_CODE=$(echo "$CALLBACK_URL" | grep -oP 'code=\K[^&]+' || true)
    CALLBACK_STATE=$(echo "$CALLBACK_URL" | grep -oP 'state=\K[^&]+' || true)

    if [[ -z "$CALLBACK_CODE" ]]; then
        error "无法从 URL 中解析 code 参数"
        error "URL 格式应为: http://localhost:1455/auth/callback?code=xxx&state=xxx"
        exit 1
    fi

    if [[ "$CALLBACK_STATE" != "$STATE" ]]; then
        error "state 不匹配，可能是过期的授权链接，请重新登录"
        exit 1
    fi

    info "授权码已获取，正在换取 token..."

    # 4. 用 code 换 token
    RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=authorization_code" \
        -d "client_id=${CLIENT_ID}" \
        -d "code=${CALLBACK_CODE}" \
        -d "redirect_uri=${REDIRECT_URI}" \
        -d "code_verifier=${CODE_VERIFIER}")

    ACCESS_TOKEN=$(json_get "$RESPONSE" "access_token")
    REFRESH_TOKEN=$(json_get "$RESPONSE" "refresh_token")
    ID_TOKEN=$(json_get "$RESPONSE" "id_token")

    if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
        error "Token 换取失败"
        error "响应: $RESPONSE"
        exit 1
    fi

    # 从 access_token JWT 中提取 account_id
    ACCOUNT_ID=$(extract_account_id "$ACCESS_TOKEN")

    # 5. 保存到 Codex CLI 配置目录
    save_codex_auth "$ID_TOKEN" "$ACCESS_TOKEN" "$REFRESH_TOKEN" "$ACCOUNT_ID"

    info "登录成功！"
    echo ""
    echo "  access_token:  ${ACCESS_TOKEN:0:20}...${ACCESS_TOKEN: -20}"
    echo "  refresh_token: ${REFRESH_TOKEN:0:20}...${REFRESH_TOKEN: -20}"
    [[ -n "$ACCOUNT_ID" ]] && echo "  account_id:    ${ACCOUNT_ID}"
    echo "  保存位置:      ${CODEX_AUTH_FILE}"
    echo ""
    info "Codex CLI 已就绪，直接运行 'codex' 即可使用"
    info "使用 '$0 refresh' 刷新 token"
    info "使用 '$0 status' 查看 token 状态"
}

# ── 刷新 Token ────────────────────────────────────────
do_refresh() {
    check_deps

    if [[ ! -f "$CODEX_AUTH_FILE" ]]; then
        error "未找到 token 文件: ${CODEX_AUTH_FILE}"
        error "请先运行: $0 login"
        exit 1
    fi

    TOKEN_JSON=$(cat "$CODEX_AUTH_FILE")
    REFRESH_TOKEN=$(json_get_nested "$TOKEN_JSON" "tokens.refresh_token")

    if [[ -z "$REFRESH_TOKEN" ]]; then
        error "无 refresh_token，请重新登录: $0 login"
        exit 1
    fi

    info "正在刷新 token..."

    RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=refresh_token" \
        -d "client_id=${CLIENT_ID}" \
        -d "refresh_token=${REFRESH_TOKEN}")

    ACCESS_TOKEN=$(json_get "$RESPONSE" "access_token")
    NEW_REFRESH=$(json_get "$RESPONSE" "refresh_token")
    ID_TOKEN=$(json_get "$RESPONSE" "id_token")

    if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
        error "Token 刷新失败"
        error "响应: $RESPONSE"
        exit 1
    fi

    [[ -z "$NEW_REFRESH" || "$NEW_REFRESH" == "null" ]] && NEW_REFRESH="$REFRESH_TOKEN"
    [[ -z "$ID_TOKEN" || "$ID_TOKEN" == "null" ]] && ID_TOKEN=$(json_get_nested "$TOKEN_JSON" "tokens.id_token")

    # 从 access_token JWT 中提取 account_id
    ACCOUNT_ID=$(extract_account_id "$ACCESS_TOKEN")
    [[ -z "$ACCOUNT_ID" ]] && ACCOUNT_ID=$(json_get_nested "$TOKEN_JSON" "tokens.account_id")

    save_codex_auth "$ID_TOKEN" "$ACCESS_TOKEN" "$NEW_REFRESH" "$ACCOUNT_ID"

    info "Token 刷新成功！"
}

# ── 查看状态 ──────────────────────────────────────────
do_status() {
    # Codex CLI 状态
    if command -v codex &>/dev/null; then
        local version
        version=$(codex --version 2>/dev/null || echo "unknown")
        info "Codex CLI: 已安装 (${version})"
    else
        warn "Codex CLI: 未安装"
    fi

    # Token 状态
    if [[ ! -f "$CODEX_AUTH_FILE" ]]; then
        warn "Token: 未登录 (未找到 ${CODEX_AUTH_FILE})"
        echo "  运行 '$0 login' 开始登录"
        exit 0
    fi

    TOKEN_JSON=$(cat "$CODEX_AUTH_FILE")
    ACCESS_TOKEN=$(json_get_nested "$TOKEN_JSON" "tokens.access_token")
    ACCOUNT_ID=$(json_get_nested "$TOKEN_JSON" "tokens.account_id")

    echo ""
    bold "Codex Token 状态"
    echo ""
    echo "  文件:          ${CODEX_AUTH_FILE}"
    echo "  access_token:  ${ACCESS_TOKEN:0:20}...${ACCESS_TOKEN: -20}"
    [[ -n "$ACCOUNT_ID" ]] && echo "  account_id:    ${ACCOUNT_ID}"
    info "状态: 已登录"
    echo ""
    echo "  提示: Codex CLI 使用自动刷新机制，无需手动检查过期时间"
    echo "  运行 '$0 refresh' 可手动刷新 token"
    echo ""
}

# ── 输出 Token ────────────────────────────────────────
do_token() {
    if [[ ! -f "$CODEX_AUTH_FILE" ]]; then
        error "未登录" >&2
        exit 1
    fi

    TOKEN_JSON=$(cat "$CODEX_AUTH_FILE")
    json_get_nested "$TOKEN_JSON" "tokens.access_token"
}

# ── 保存 Token 到 Codex CLI 格式 ─────────────────────
save_codex_auth() {
    local id_token="$1" access_token="$2" refresh_token="$3" account_id="$4"

    # 确保目录存在
    mkdir -p "$CODEX_HOME"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
tokens = {
    'id_token': sys.argv[1],
    'access_token': sys.argv[2],
    'refresh_token': sys.argv[3]
}
if sys.argv[4]:
    tokens['account_id'] = sys.argv[4]
d = {'tokens': tokens}
print(json.dumps(d, indent=2))
" "$id_token" "$access_token" "$refresh_token" "$account_id" > "$CODEX_AUTH_FILE"
    elif command -v jq &>/dev/null; then
        jq -n \
            --arg it "$id_token" \
            --arg at "$access_token" \
            --arg rt "$refresh_token" \
            --arg aid "$account_id" \
            '{tokens: {id_token: $it, access_token: $at, refresh_token: $rt} + (if $aid != "" then {account_id: $aid} else {} end)}' > "$CODEX_AUTH_FILE"
    else
        # Fallback: 手动构建 JSON
        cat > "$CODEX_AUTH_FILE" <<JSONEOF
{
  "tokens": {
    "id_token": "$id_token",
    "access_token": "$access_token",
    "refresh_token": "$refresh_token"$(if [[ -n "$account_id" ]]; then echo ",
    \"account_id\": \"$account_id\""; fi)
  }
}
JSONEOF
    fi

    chmod 600 "$CODEX_AUTH_FILE"
}

# ── 帮助 ──────────────────────────────────────────────
do_help() {
    echo ""
    bold "Codex for Linux — ChatGPT Codex OAuth 登录工具"
    echo ""
    echo "用法: $0 <命令>"
    echo ""
    echo "命令:"
    echo "  login    检测/安装 Codex CLI，登录 ChatGPT 获取 token"
    echo "  refresh  刷新 access_token"
    echo "  status   查看 Codex CLI 和 token 状态"
    echo "  token    输出 access_token (可用于管道)"
    echo "  help     显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 login                          # 登录"
    echo "  $0 status                          # 查看状态"
    echo "  codex                               # 登录后直接使用 Codex CLI"
    echo ""
    echo "Token 保存位置: ${CODEX_AUTH_FILE}"
    echo ""
}

# ── 主入口 ────────────────────────────────────────────
case "${1:-help}" in
    login)   do_login ;;
    refresh) do_refresh ;;
    status)  do_status ;;
    token)   do_token ;;
    help|--help|-h) do_help ;;
    *)
        error "未知命令: $1"
        do_help
        exit 1
        ;;
esac
