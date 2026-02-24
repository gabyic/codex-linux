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
TOKEN_FILE="${CODEX_TOKEN_FILE:-$HOME/.codex-token.json}"

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
    base64 -w0 | tr '+/' '-_' | tr -d '='
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
    # 尝试 jq
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$key // empty"
        return
    fi
    # 尝试 python3
    if command -v python3 &>/dev/null; then
        python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('$key',''))" <<< "$json"
        return
    fi
    # 最后用 grep（简单场景）
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
    EXPIRES_IN=$(json_get_num "$RESPONSE" "expires_in")

    if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
        error "Token 换取失败"
        error "响应: $RESPONSE"
        exit 1
    fi

    EXPIRES_AT=$(( $(date +%s) + EXPIRES_IN ))

    # 5. 保存 token
    save_token "$ACCESS_TOKEN" "$REFRESH_TOKEN" "$EXPIRES_AT"

    info "登录成功！Token 已保存到 ${TOKEN_FILE}"
    echo ""
    echo "  access_token:  ${ACCESS_TOKEN:0:20}...${ACCESS_TOKEN: -20}"
    echo "  refresh_token: ${REFRESH_TOKEN:0:20}...${REFRESH_TOKEN: -20}"
    echo "  过期时间:      $(date -d "@$EXPIRES_AT" 2>/dev/null || date -r "$EXPIRES_AT" 2>/dev/null || echo "$EXPIRES_AT")"
    echo ""
    info "使用 '$0 token' 获取 access_token"
    info "使用 '$0 refresh' 刷新 token"
}

# ── 刷新 Token ────────────────────────────────────────
do_refresh() {
    check_deps

    if [[ ! -f "$TOKEN_FILE" ]]; then
        error "未找到 token 文件: $TOKEN_FILE"
        error "请先运行: $0 login"
        exit 1
    fi

    TOKEN_JSON=$(cat "$TOKEN_FILE")
    REFRESH_TOKEN=$(json_get "$TOKEN_JSON" "refresh_token")

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
    EXPIRES_IN=$(json_get_num "$RESPONSE" "expires_in")

    if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
        error "Token 刷新失败"
        error "响应: $RESPONSE"
        exit 1
    fi

    # refresh_token 可能更新也可能不变
    [[ -z "$NEW_REFRESH" || "$NEW_REFRESH" == "null" ]] && NEW_REFRESH="$REFRESH_TOKEN"

    EXPIRES_AT=$(( $(date +%s) + EXPIRES_IN ))
    save_token "$ACCESS_TOKEN" "$NEW_REFRESH" "$EXPIRES_AT"

    info "Token 刷新成功！"
    echo "  过期时间: $(date -d "@$EXPIRES_AT" 2>/dev/null || date -r "$EXPIRES_AT" 2>/dev/null || echo "$EXPIRES_AT")"
}

# ── 查看状态 ──────────────────────────────────────────
do_status() {
    if [[ ! -f "$TOKEN_FILE" ]]; then
        warn "未登录 (未找到 ${TOKEN_FILE})"
        echo "  运行 '$0 login' 开始登录"
        exit 0
    fi

    TOKEN_JSON=$(cat "$TOKEN_FILE")
    ACCESS_TOKEN=$(json_get "$TOKEN_JSON" "access_token")
    EXPIRES_AT=$(json_get_num "$TOKEN_JSON" "expires_at")
    NOW=$(date +%s)

    echo ""
    bold "Codex Token 状态"
    echo ""
    echo "  文件:          $TOKEN_FILE"
    echo "  access_token:  ${ACCESS_TOKEN:0:20}...${ACCESS_TOKEN: -20}"

    if [[ "$EXPIRES_AT" -gt "$NOW" ]]; then
        REMAINING=$(( EXPIRES_AT - NOW ))
        HOURS=$(( REMAINING / 3600 ))
        MINS=$(( (REMAINING % 3600) / 60 ))
        info "状态: 有效（剩余 ${HOURS}h ${MINS}m）"
        echo "  过期时间: $(date -d "@$EXPIRES_AT" 2>/dev/null || date -r "$EXPIRES_AT" 2>/dev/null || echo "$EXPIRES_AT")"
    else
        error "状态: 已过期"
        echo "  运行 '$0 refresh' 刷新 token"
    fi
    echo ""
}

# ── 输出 Token ────────────────────────────────────────
do_token() {
    if [[ ! -f "$TOKEN_FILE" ]]; then
        error "未登录" >&2
        exit 1
    fi

    TOKEN_JSON=$(cat "$TOKEN_FILE")
    EXPIRES_AT=$(json_get_num "$TOKEN_JSON" "expires_at")
    NOW=$(date +%s)

    # 自动刷新（过期前 60 秒）
    if [[ "$EXPIRES_AT" -le $(( NOW + 60 )) ]]; then
        warn "Token 即将过期，自动刷新..." >&2
        do_refresh >&2
        TOKEN_JSON=$(cat "$TOKEN_FILE")
    fi

    json_get "$TOKEN_JSON" "access_token"
}

# ── 保存 Token ────────────────────────────────────────
save_token() {
    local access_token="$1" refresh_token="$2" expires_at="$3"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json
d = {'access_token': '''$access_token''', 'refresh_token': '''$refresh_token''', 'expires_at': $expires_at}
print(json.dumps(d, indent=2))
" > "$TOKEN_FILE"
    elif command -v jq &>/dev/null; then
        jq -n \
            --arg at "$access_token" \
            --arg rt "$refresh_token" \
            --argjson ea "$expires_at" \
            '{access_token: $at, refresh_token: $rt, expires_at: $ea}' > "$TOKEN_FILE"
    else
        cat > "$TOKEN_FILE" <<JSONEOF
{
  "access_token": "$access_token",
  "refresh_token": "$refresh_token",
  "expires_at": $expires_at
}
JSONEOF
    fi

    chmod 600 "$TOKEN_FILE"
}

# ── 帮助 ──────────────────────────────────────────────
do_help() {
    echo ""
    bold "Codex for Linux — ChatGPT Codex OAuth 登录工具"
    echo ""
    echo "用法: $0 <命令>"
    echo ""
    echo "命令:"
    echo "  login    登录 ChatGPT，获取 Codex API token"
    echo "  refresh  刷新 access_token"
    echo "  status   查看 token 状态"
    echo "  token    输出 access_token（可用于管道）"
    echo "  help     显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 login                          # 登录"
    echo "  $0 token                           # 获取 token"
    echo '  curl -H "Authorization: Bearer $($0 token)" ...  # 配合 curl 使用'
    echo ""
    echo "环境变量:"
    echo "  CODEX_TOKEN_FILE  token 保存路径（默认: ~/.codex-token.json）"
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
