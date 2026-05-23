#!/usr/bin/env bash
set -euo pipefail

# ── 终端美化：切换到 Pro 主题（深色背景、大字体）并调整窗口 ──────────────────────
if [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
  printf '\033[36m==> 正在优化终端显示效果...\033[0m\n'
  osascript -e '
  tell application "Terminal"
    -- 修改 Pro 主题的字体大小（固化到主题本身）
    set font name of settings set "Pro" to "Menlo"
    set font size of settings set "Pro" to 14
    -- 设为默认
    set default settings to settings set "Pro"
    set startup settings to settings set "Pro"
    -- 应用到当前窗口
    set currentTab to selected tab of front window
    set current settings of currentTab to settings set "Pro"
    tell front window
      set bounds to {60, 60, 1000, 750}
    end tell
  end tell
  ' 2>/dev/null || true
  printf '\033[32mOK  已切换为深色主题、14号字体，并设为默认\033[0m\n'
fi

DRY_RUN=0
YES=0
SKIP_OPTIONAL=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) YES=1 ;;
    --skip-optional) SKIP_OPTIONAL=1 ;;
    *) echo "Unknown argument: $arg"; exit 2 ;;
  esac
done

APP_NAME="Claude + DeepSeek Setup"
WORKSPACE="$HOME/ClaudeDeepSeekWorkspace"
STATE_DIR="$HOME/.claude-deepseek-setup"
LOG_FILE="$STATE_DIR/setup.log"
STATE_FILE="$STATE_DIR/state.tsv"
DEEPSEEK_BASE_URL="https://api.deepseek.com"
NPM_REGISTRIES=(
  "https://registry.npmmirror.com"
  "https://registry.npmjs.org"
)
PIP_INDEXES=(
  "https://pypi.tuna.tsinghua.edu.cn/simple"
  "https://mirrors.aliyun.com/pypi/simple"
  "https://repo.huaweicloud.com/repository/pypi/simple"
  "https://pypi.org/simple"
)
HOMEBREW_BREW_GIT_REMOTE_DEFAULT="https://mirrors.aliyun.com/homebrew/brew.git"
HOMEBREW_CORE_GIT_REMOTE_DEFAULT="https://mirrors.aliyun.com/homebrew/homebrew-core.git"
HOMEBREW_API_DOMAIN_DEFAULT="https://mirrors.aliyun.com/homebrew/homebrew-bottles/api"
HOMEBREW_BOTTLE_DOMAIN_DEFAULT="https://mirrors.aliyun.com/homebrew/homebrew-bottles"

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE"
}

step() {
  printf '\n\033[36m==> %s\033[0m\n' "$*"
  log "STEP $*"
}

ok() {
  printf '\033[32mOK  %s\033[0m\n' "$*"
  log "OK $*"
}

warn() {
  printf '\033[33m!!  %s\033[0m\n' "$*"
  log "WARN $*"
}

fail() {
  printf '\033[31mXX  %s\033[0m\n' "$*"
  log "FAIL $*"
}

run() {
  log "RUN $*"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY %s\033[0m\n' "$*"
    return 0
  fi
  "$@" >> "$LOG_FILE" 2>&1
}

try_run() {
  log "RUN $*"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY %s\033[0m\n' "$*"
    return 0
  fi
  "$@" >> "$LOG_FILE" 2>&1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# ── 进度指示器 ──────────────────────────────────────────────────────────────────
SPINNER_PID=""
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

spinner_start() {
  local msg="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi
  (
    local i=0
    local elapsed=0
    while true; do
      local frame="${SPINNER_FRAMES[$((i % ${#SPINNER_FRAMES[@]}))]}"
      printf '\r\033[33m%s %s (%ds)\033[0m' "$frame" "$msg" "$elapsed"
      sleep 1
      elapsed=$((elapsed + 1))
      i=$((i + 1))
    done
  ) &
  SPINNER_PID=$!
  disown "$SPINNER_PID" 2>/dev/null
}

spinner_stop() {
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    printf '\r\033[K'
  fi
}

# 带进度指示的命令执行
run_with_progress() {
  local msg="$1"
  shift
  log "RUN $*"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY %s\033[0m\n' "$*"
    return 0
  fi
  spinner_start "$msg"
  local exit_code=0
  "$@" >> "$LOG_FILE" 2>&1 || exit_code=$?
  spinner_stop
  return $exit_code
}

# 带进度指示的管道命令执行（用于 Homebrew 安装等需要 shell 解释的命令）
run_shell_with_progress() {
  local msg="$1"
  local cmd="$2"
  log "RUN $cmd"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY %s\033[0m\n' "$cmd"
    return 0
  fi
  spinner_start "$msg"
  local exit_code=0
  bash -c "$cmd" >> "$LOG_FILE" 2>&1 || exit_code=$?
  spinner_stop
  return $exit_code
}

# 确保脚本退出时清理 spinner
cleanup_spinner() {
  spinner_stop
}
trap 'cleanup_spinner; fail "安装没有完全完成。修复错误后可重复运行，日志: $LOG_FILE"; deepseek_diagnose "脚本意外退出" ""' ERR
trap 'cleanup_spinner' EXIT

# ── DeepSeek AI 助手集成 ────────────────────────────────────────────────────────
# 当安装步骤失败时，自动调用 DeepSeek 分析错误并给出建议

deepseek_ask() {
  local question="$1"
  local context="${2:-}"
  local key="${DEEPSEEK_KEY:-}"

  # 如果脚本还没收集到 key，尝试从环境变量或 rc 文件读取
  if [[ -z "$key" ]]; then
    key="${DEEPSEEK_API_KEY:-}"
  fi
  if [[ -z "$key" ]]; then
    local rc="$HOME/.zshrc"
    [[ "$(basename "${SHELL:-zsh}")" == "bash" ]] && rc="$HOME/.bash_profile"
    if [[ -f "$rc" ]]; then
      key="$(grep -E "^export DEEPSEEK_API_KEY=" "$rc" | tail -n 1 | sed -E 's/^export DEEPSEEK_API_KEY="?//; s/"?$//' || true)"
    fi
  fi

  if [[ -z "$key" ]]; then
    printf '\033[90m    (未配置 DeepSeek Key，无法调用 AI 助手)\033[0m\n'
    return 1
  fi

  local env_info
  env_info="$(printf 'macOS: %s\nHomebrew: %s\nNode: %s\nnpm: %s\nPython: %s\nClaude: %s\n' \
    "$(sw_vers -productVersion 2>/dev/null || echo unknown)" \
    "$(command -v brew >/dev/null 2>&1 && echo 已安装 || echo 未安装)" \
    "$(command -v node >/dev/null 2>&1 && echo 已安装 || echo 未安装)" \
    "$(command -v npm >/dev/null 2>&1 && echo 已安装 || echo 未安装)" \
    "$(command -v python3 >/dev/null 2>&1 && echo 已安装 || echo 未安装)" \
    "$(command -v claude >/dev/null 2>&1 && echo 已安装 || echo 未安装)")"

  local skill
  skill="你是面向电脑小白的安装助手。用简体中文回答。给出最多3个具体下一步。先解释错误含义，再给修复方案。给出的命令要说明在哪里运行。"

  local system_content user_content payload response answer
  system_content="$skill"
  user_content="$(printf '当前环境:\n%s\n\n%s\n\n用户问题:\n%s' "$env_info" "$context" "$question")"

  # JSON escape using perl
  local sys_json usr_json
  sys_json="$(printf '%s' "$system_content" | perl -MJSON::PP -0777 -ne 'print encode_json($_)' 2>/dev/null || printf '"%s"' "$system_content")"
  usr_json="$(printf '%s' "$user_content" | perl -MJSON::PP -0777 -ne 'print encode_json($_)' 2>/dev/null || printf '"%s"' "$user_content")"

  payload="{\"model\":\"deepseek-v4-flash\",\"messages\":[{\"role\":\"system\",\"content\":$sys_json},{\"role\":\"user\",\"content\":$usr_json}],\"stream\":false,\"temperature\":0.2}"

  response="$(curl -sS --connect-timeout 10 --max-time 30 \
    "${DEEPSEEK_BASE_URL}/chat/completions" \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)" || {
    printf '\033[90m    (DeepSeek 请求失败，请检查网络)\033[0m\n'
    return 1
  }

  answer="$(printf '%s' "$response" | perl -MJSON::PP -0777 -ne 'my $d = decode_json($_); print $d->{choices}[0]{message}{content}' 2>/dev/null)" || {
    printf '\033[90m    (DeepSeek 返回格式异常)\033[0m\n'
    return 1
  }

  printf '\n\033[35m┌─ DeepSeek 助手 ─────────────────────────────────────────┐\033[0m\n'
  printf '%s\n' "$answer" | while IFS= read -r line; do
    printf '\033[35m│\033[0m %s\n' "$line"
  done
  printf '\033[35m└────────────────────────────────────────────────────────────┘\033[0m\n\n'
}

# 步骤失败时自动调用 DeepSeek 分析
deepseek_diagnose() {
  local step_name="$1"
  local error_detail="${2:-}"

  printf '\n\033[33m    正在请求 DeepSeek 分析错误原因...\033[0m\n'

  local log_tail
  log_tail="$(tail -20 "$LOG_FILE" 2>/dev/null || echo "")"

  local context="最近日志:\n$log_tail"
  [[ -n "$error_detail" ]] && context="$context\n\n额外错误信息:\n$error_detail"

  deepseek_ask "安装步骤「${step_name}」失败了，请分析原因并告诉我怎么修复。" "$context"
}

# 允许用户随时输入问题问 DeepSeek
deepseek_interactive_help() {
  printf '\033[36m    输入你的问题（直接回车跳过）: \033[0m'
  local question
  read -r question
  if [[ -n "$question" ]]; then
    local log_tail
    log_tail="$(tail -10 "$LOG_FILE" 2>/dev/null || echo "")"
    deepseek_ask "$question" "最近日志:\n$log_tail"
  fi
}

confirm() {
  local question="$1"
  local default="${2:-yes}"
  if [[ "$YES" == "1" ]]; then
    return 0
  fi
  local suffix="[Y/n]"
  [[ "$default" == "no" ]] && suffix="[y/N]"
  local answer=""
  read -r -p "$question $suffix " answer || true
  if [[ -z "$answer" ]]; then
    [[ "$default" == "yes" ]]
    return
  fi
  local answer_lc
  answer_lc="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
  [[ "$answer_lc" == y* ]]
}

save_state() {
  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi
  printf '%s\t%s\t%s\n' "$1" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE_FILE"
}

default_deepseek_skill() {
  cat <<'EOF'
# DeepSeek Setup Guide Skill

Purpose:
Guide beginners through installing and using Claude Code with DeepSeek on Windows/macOS, with minimal jargon and safe defaults.

Conversation Rules:
1. Always answer in simplified Chinese unless the user asks otherwise.
2. Start by identifying the user's current stage: key setup, environment detection, dependency install, Claude launch, DeepSeek test, or error repair.
3. Give at most three concrete next steps. Prefer one next action when the user is confused.
4. Explain what a message means before giving a fix.
5. Never ask the user to paste or reveal API keys. If a key is needed, say "请在输入框里保存 Key".
6. When commands are needed, give the exact command and say where to run it: PowerShell, Terminal, or this program.
7. Prefer the program's buttons first: 保存 Key, 检测环境, 一键启动安装, 打开工作区, 打开终端运行 Claude.
8. If something is already configured, tell the user to keep it unless they intentionally want to replace it.
9. For risky actions such as overwriting files, changing environment variables, reinstalling tools, or deleting anything, tell the user to confirm first.
10. If network, permission, Homebrew, npm, Python, or Claude install errors appear, ask for the exact red error text and give a small checklist.
11. 默认镜像策略是国内优先：Claude Code 先用 npm 国内镜像，npm/pip/Homebrew 也优先使用国内镜像，失败再回到官方源。

Decision Flow:
- No DeepSeek key: tell the user to paste the key into the input box and click 保存 Key.
- Key saved but tools missing: tell the user to click 一键启动安装.
- Install finished: tell the user to reopen Terminal or click 打开终端运行 Claude.
- Claude works: tell the user they can type natural language tasks after the claude prompt appears.
- DeepSeek call fails: check key correctness, network access, quota/balance, and API endpoint.
- User is lost: summarize current environment in plain words, then give only the next button to click.

Answer Format:
第一句：一句话说明当前情况。
然后：
1. 下一步
2. 如果失败，复制哪段报错
3. 成功后会看到什么
EOF
}

mask_value() {
  local value="$1"
  if [[ -z "$value" ]]; then
    printf '<empty>'
  elif [[ "${#value}" -le 8 ]]; then
    printf '********'
  else
    printf '%s...%s' "${value:0:4}" "${value: -4}"
  fi
}

append_env() {
  local name="$1"
  local value="$2"

  step "写入用户环境变量 ${name}"

  local shell_name
  shell_name="$(basename "${SHELL:-zsh}")"
  local rc="$HOME/.zshrc"
  [[ "$shell_name" == "bash" ]] && rc="$HOME/.bash_profile"

  local current=""
  current="$(printenv "$name" 2>/dev/null)" || current=""
  if [[ -z "$current" && -f "$rc" ]]; then
    current="$(grep -E "^export $name=" "$rc" | tail -n 1 | sed -E "s/^export $name=\"?//; s/\"?$//" || true)"
  fi

  if [[ -n "$current" ]]; then
    warn "${name} 已配置为 $(mask_value "$current")"
    if [[ -z "$value" ]]; then
      ok "未输入新值，保留现有 ${name}"
      save_state "env:$name" "kept"
      return 0
    fi
    if ! confirm "是否覆盖 ${name} ？" "no"; then
      ok "保留现有 ${name}"
      save_state "env:$name" "kept"
      return 0
    fi
  fi

  [[ -z "$value" ]] && return 0
  export "$name=$value"

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY append export %s=*** to %s\033[0m\n' "$name" "$rc"
    return 0
  fi

  touch "$rc"
  if grep -q "^export $name=" "$rc"; then
    perl -0pi -e "s|^export $name=.*$|export $name=\"$value\"|mg" "$rc"
  else
    printf '\nexport %s="%s"\n' "$name" "$value" >> "$rc"
  fi
  save_state "env:$name" "set"
}

configure_mirrors() {
  step "配置国内镜像源"

  if command -v npm >/dev/null 2>&1; then
    for registry in "${NPM_REGISTRIES[@]}"; do
      if try_run npm config set registry "$registry"; then
        ok "npm 镜像已设置为 $registry"
        save_state "mirror:npm" "$registry"
        break
      fi
    done
  else
    warn "未检测到 npm，稍后安装 Node.js 后会再次尝试"
  fi

  if command -v python3 >/dev/null 2>&1; then
    for index in "${PIP_INDEXES[@]}"; do
      if try_run python3 -m pip config set global.index-url "$index"; then
        ok "pip 镜像已设置为 $index"
        save_state "mirror:pip" "$index"
        break
      fi
    done
  else
    warn "未检测到 python3，跳过 pip 镜像配置"
  fi

  append_env "HOMEBREW_BREW_GIT_REMOTE" "${HOMEBREW_BREW_GIT_REMOTE:-$HOMEBREW_BREW_GIT_REMOTE_DEFAULT}"
  append_env "HOMEBREW_CORE_GIT_REMOTE" "${HOMEBREW_CORE_GIT_REMOTE:-$HOMEBREW_CORE_GIT_REMOTE_DEFAULT}"
  append_env "HOMEBREW_API_DOMAIN" "${HOMEBREW_API_DOMAIN:-$HOMEBREW_API_DOMAIN_DEFAULT}"
  append_env "HOMEBREW_BOTTLE_DOMAIN" "${HOMEBREW_BOTTLE_DOMAIN:-$HOMEBREW_BOTTLE_DOMAIN_DEFAULT}"
}

write_workspace_file() {
  local relative_path="$1"
  local sensitive="${2:-no}"
  local target="$WORKSPACE/$relative_path"
  mkdir -p "$(dirname "$target")"

  if [[ -f "$target" ]]; then
    local label="$relative_path"
    [[ "$sensitive" == "yes" ]] && label="${relative_path}（包含本机密钥）"
    warn "$label 已存在"
    if ! confirm "是否覆盖 ${relative_path} ？" "no"; then
      ok "保留 ${relative_path}"
      save_state "workspace:$relative_path" "kept"
      cat >/dev/null
      return 0
    fi
  fi

  cat > "$target"
  save_state "workspace:$relative_path" "written"
}

install_brew_if_needed() {
  if has_cmd brew; then
    ok "Homebrew 可用"
    return
  fi

  step "安装 Homebrew"
  export HOMEBREW_BREW_GIT_REMOTE="${HOMEBREW_BREW_GIT_REMOTE:-$HOMEBREW_BREW_GIT_REMOTE_DEFAULT}"
  export HOMEBREW_CORE_GIT_REMOTE="${HOMEBREW_CORE_GIT_REMOTE:-$HOMEBREW_CORE_GIT_REMOTE_DEFAULT}"
  export HOMEBREW_API_DOMAIN="${HOMEBREW_API_DOMAIN:-$HOMEBREW_API_DOMAIN_DEFAULT}"
  export HOMEBREW_BOTTLE_DOMAIN="${HOMEBREW_BOTTLE_DOMAIN:-$HOMEBREW_BOTTLE_DOMAIN_DEFAULT}"
  if ! confirm "未检测到 Homebrew，是否安装？" "yes"; then
    fail "Homebrew 是 macOS 自动安装依赖的基础，请安装后重新运行"
    exit 1
  fi
  printf '    提示: Homebrew 安装包较大，可能需要 5-15 分钟，请耐心等待\n'
  printf '    安装过程中可能需要输入电脑密码（sudo），请留意提示\n\n'
  log "RUN Homebrew official installer (interactive, output to terminal)"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\033[0m\n'
  else
    # Homebrew 安装需要用户交互（sudo 密码），所以输出直接到终端而非日志
    local brew_exit=0
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | tee -a "$LOG_FILE" || brew_exit=$?
    if [[ "$brew_exit" -ne 0 ]]; then
      fail "Homebrew 安装脚本返回错误 (exit code: $brew_exit)"
      deepseek_diagnose "安装 Homebrew" "curl 下载或安装脚本执行失败，exit code: $brew_exit"
      if ! confirm "是否重试？" "yes"; then
        exit 1
      fi
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | tee -a "$LOG_FILE"
    fi
  fi

  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  ok "Homebrew 已安装"
}

brew_install() {
  local package="$1"
  local display="$2"
  local cmd_name="${3:-}"  # 可选：对应的命令名，用于检测系统是否已有

  # 如果提供了命令名，先检查系统是否已有该命令
  if [[ -n "$cmd_name" ]] && command -v "$cmd_name" >/dev/null 2>&1; then
    local existing_ver
    existing_ver="$("$cmd_name" --version 2>/dev/null | head -1 || echo "已安装")"
    ok "$display 已可用 ($existing_ver)"
    if ! confirm "系统已有 ${display}，是否仍通过 Homebrew 安装/升级？" "no"; then
      ok "跳过 $display"
      save_state "$package" "system-present"
      return
    fi
  fi

  step "检测 $display"
  if brew list "$package" >/dev/null 2>&1 || brew list --cask "$package" >/dev/null 2>&1; then
    ok "$display 已安装"
    save_state "$package" "present"
    return
  fi

  step "安装 $display"
  local exit_code=0
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY brew install %s\033[0m\n' "$package"
    save_state "$package" "installed"
    return
  fi

  # 直接输出到终端，让用户看到详细的下载和安装进度
  # --verbose 让 brew 显示下载进度和详细步骤
  if [[ "$package" == "visual-studio-code" || "$package" == "docker" || "$package" == "claude-code" ]]; then
    brew install --cask --verbose "$package" 2>&1 | tee -a "$LOG_FILE" || exit_code=$?
  else
    brew install --verbose "$package" 2>&1 | tee -a "$LOG_FILE" || exit_code=$?
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    fail "$display 安装失败 (exit code: $exit_code)"
    deepseek_diagnose "安装 $display" "brew install $package 返回错误码 $exit_code"
    if confirm "是否跳过此步骤继续？" "no"; then
      warn "已跳过 $display"
      save_state "$package" "skipped"
      return 0
    fi
    exit 1
  fi

  ok "$display 安装完成"
  save_state "$package" "installed"
}

ensure_workspace() {
  local deepseek_key="$1"
  local anthropic_key="$2"

  step "创建默认工作区"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY create %s\033[0m\n' "$WORKSPACE"
    return 0
  fi

  mkdir -p "$WORKSPACE/skills/deepseek-automation"

  write_workspace_file ".env" "yes" <<EOF
DEEPSEEK_API_KEY=$deepseek_key
DEEPSEEK_BASE_URL=$DEEPSEEK_BASE_URL
ANTHROPIC_API_KEY=$anthropic_key
EOF

  write_workspace_file ".env.example" <<'EOF'
DEEPSEEK_API_KEY=your_deepseek_api_key
DEEPSEEK_BASE_URL=https://api.deepseek.com
ANTHROPIC_API_KEY=your_anthropic_api_key_optional
EOF

  write_workspace_file ".gitignore" <<'EOF'
.env
.venv/
node_modules/
dist/
build/
__pycache__/
EOF

  write_workspace_file "CLAUDE.md" <<'EOF'
# Claude + DeepSeek Workspace

你是这个工作区的自动化开发助手。

默认策略：
- 复杂项目理解、架构设计、重构和长上下文分析优先交给 Claude。
- 中文批处理、低成本文本处理和简单代码生成优先使用 DeepSeek。
- API Key 从环境变量读取，不要写进代码或提交到 Git。
- 修改代码前先检测环境、确认依赖、再执行最小必要改动。

常用环境变量：
- DEEPSEEK_API_KEY
- DEEPSEEK_BASE_URL
- ANTHROPIC_API_KEY
EOF

  default_deepseek_skill | write_workspace_file "skills/deepseek-automation/SKILL.md"

  write_workspace_file "deepseek_smoke_test.py" <<'EOF'
import os
import json
import urllib.request

api_key = os.environ.get("DEEPSEEK_API_KEY")
base_url = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")

if not api_key:
    raise SystemExit("DEEPSEEK_API_KEY is not set")

payload = {
    "model": "deepseek-v4-flash",
    "messages": [
        {"role": "system", "content": "You are a concise setup verifier."},
        {"role": "user", "content": "Reply with: DeepSeek OK"}
    ],
    "stream": False
}

request = urllib.request.Request(
    base_url + "/chat/completions",
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Authorization": "Bearer " + api_key,
        "Content-Type": "application/json",
    },
    method="POST",
)

with urllib.request.urlopen(request, timeout=30) as response:
    data = json.loads(response.read().decode("utf-8"))
    print(data["choices"][0]["message"]["content"])
EOF

  save_state "workspace" "created"
  ok "工作区已创建: $WORKSPACE"
}

log "START $APP_NAME"

printf '\n\033[36mClaude + DeepSeek 空白电脑安装向导\033[0m\n'
printf '这个工具会检测环境、安装依赖、配置 API Key，并验证终端里的 claude 命令。\n'
printf '💡 安装过程中如果遇到问题，DeepSeek AI 助手会自动分析并给出建议。\n'
printf '日志: %s\n\n' "$LOG_FILE"

read -r -p "请输入 DeepSeek API Key，也可以直接回车稍后再配: " DEEPSEEK_KEY
read -r -p "可选：请输入 Anthropic API Key，也可以直接回车使用 Claude 登录流程: " ANTHROPIC_KEY

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "这个脚本适用于 macOS。Windows 请运行 claude-deepseek-setup.ps1"
  exit 1
fi

# 强制设置 Homebrew 镜像源（覆盖 ~/.zshrc 中可能过期的配置）
export HOMEBREW_BREW_GIT_REMOTE="$HOMEBREW_BREW_GIT_REMOTE_DEFAULT"
export HOMEBREW_CORE_GIT_REMOTE="$HOMEBREW_CORE_GIT_REMOTE_DEFAULT"
export HOMEBREW_API_DOMAIN="$HOMEBREW_API_DOMAIN_DEFAULT"
export HOMEBREW_BOTTLE_DOMAIN="$HOMEBREW_BOTTLE_DOMAIN_DEFAULT"

install_brew_if_needed
configure_mirrors

# ── 安装 Node.js（优先国内镜像 pkg 直装，回退 brew）────────────────────────────
install_node() {
  if command -v node >/dev/null 2>&1; then
    local ver
    ver="$(node -v 2>/dev/null)"
    ok "Node.js 已可用 ($ver)"
    if confirm "系统已有 Node.js，是否跳过？" "yes"; then
      save_state "node" "system-present"
      return
    fi
  fi

  step "安装 Node.js LTS"

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY install Node.js via npmmirror pkg\033[0m\n'
    save_state "node" "installed"
    return
  fi

  # 优先从国内镜像下载 pkg 安装包
  local node_version="v22.15.0"
  local pkg_url="https://npmmirror.com/mirrors/node/${node_version}/node-${node_version}.pkg"
  local pkg_file="$STATE_DIR/node-${node_version}.pkg"

  printf '    从国内镜像下载 Node.js %s ...\n' "$node_version"
  if curl -L --progress-bar --connect-timeout 15 --max-time 300 -o "$pkg_file" "$pkg_url" 2>&1; then
    printf '    正在安装 Node.js（可能需要输入密码）...\n'
    if sudo installer -pkg "$pkg_file" -target / >> "$LOG_FILE" 2>&1; then
      rm -f "$pkg_file"
      ok "Node.js 安装完成 ($(node -v 2>/dev/null || echo $node_version))"
      save_state "node" "installed"
      return
    fi
  fi

  # 回退到 brew
  warn "国内镜像下载失败，尝试通过 Homebrew 安装..."
  brew install --verbose node 2>&1 | tee -a "$LOG_FILE" || {
    fail "Node.js 安装失败"
    deepseek_diagnose "安装 Node.js" "npmmirror pkg 下载和 brew install node 均失败"
    exit 1
  }
  ok "Node.js 安装完成"
  save_state "node" "installed"
}

# ── 安装 Python（优先国内镜像 pkg 直装，回退 brew）──────────────────────────────
install_python() {
  if command -v python3 >/dev/null 2>&1; then
    local ver
    ver="$(python3 --version 2>/dev/null)"
    ok "Python 已可用 ($ver)"
    if confirm "系统已有 Python，是否跳过？" "yes"; then
      save_state "python" "system-present"
      return
    fi
  fi

  step "安装 Python 3.12"

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY install Python via npmmirror pkg\033[0m\n'
    save_state "python" "installed"
    return
  fi

  # 优先从国内镜像下载 pkg
  local py_version="3.12.7"
  local pkg_url="https://npmmirror.com/mirrors/python/${py_version}/python-${py_version}-macos11.pkg"
  local pkg_file="$STATE_DIR/python-${py_version}.pkg"

  printf '    从国内镜像下载 Python %s ...\n' "$py_version"
  if curl -L --progress-bar --connect-timeout 15 --max-time 300 -o "$pkg_file" "$pkg_url" 2>&1; then
    printf '    正在安装 Python（可能需要输入密码）...\n'
    if sudo installer -pkg "$pkg_file" -target / >> "$LOG_FILE" 2>&1; then
      rm -f "$pkg_file"
      ok "Python 安装完成 ($(python3 --version 2>/dev/null || echo $py_version))"
      save_state "python" "installed"
      return
    fi
  fi

  # 回退到 brew
  warn "国内镜像下载失败，尝试通过 Homebrew 安装..."
  brew install --verbose python@3.12 2>&1 | tee -a "$LOG_FILE" || {
    fail "Python 安装失败"
    deepseek_diagnose "安装 Python" "npmmirror pkg 下载和 brew install python 均失败"
    exit 1
  }
  ok "Python 安装完成"
  save_state "python" "installed"
}

install_node
install_python

append_env "DEEPSEEK_API_KEY" "$DEEPSEEK_KEY"
append_env "DEEPSEEK_BASE_URL" "$DEEPSEEK_BASE_URL"

# 配置 Claude Code 使用 DeepSeek API（Anthropic 兼容端点）
step "配置 Claude Code 使用 DeepSeek"
append_env "ANTHROPIC_BASE_URL" "https://api.deepseek.com/anthropic"
append_env "ANTHROPIC_AUTH_TOKEN" "$DEEPSEEK_KEY"
append_env "ANTHROPIC_MODEL" "deepseek-v4-pro"

step "安装 Claude Code"
if has_cmd claude; then
  ok "Claude Code 已安装 ($(claude --version 2>/dev/null | head -1 || echo ""))"
  if ! confirm "是否重新安装/覆盖 Claude Code？" "no"; then
    save_state "claude-code" "kept"
  else
    printf '    正在通过 npm 国内镜像安装 Claude Code...\n'
    sudo npm install -g @anthropic-ai/claude-code --registry https://registry.npmmirror.com 2>&1 | tee -a "$LOG_FILE" || {
      warn "npm 国内镜像失败，尝试官方源..."
      sudo npm install -g @anthropic-ai/claude-code --registry https://registry.npmjs.org 2>&1 | tee -a "$LOG_FILE" || {
        fail "Claude Code 安装失败"
        deepseek_diagnose "安装 Claude Code" "npm install -g @anthropic-ai/claude-code 失败"
        exit 1
      }
    }
    ok "Claude Code 安装完成"
    save_state "claude-code" "installed"
  fi
else
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY npm install -g @anthropic-ai/claude-code\033[0m\n'
  else
    printf '    正在通过 npm 国内镜像安装 Claude Code...\n'
    sudo npm install -g @anthropic-ai/claude-code --registry https://registry.npmmirror.com 2>&1 | tee -a "$LOG_FILE" || {
      warn "npm 国内镜像失败，尝试官方源..."
      sudo npm install -g @anthropic-ai/claude-code --registry https://registry.npmjs.org 2>&1 | tee -a "$LOG_FILE" || {
        fail "Claude Code 安装失败"
        deepseek_diagnose "安装 Claude Code" "npm install -g @anthropic-ai/claude-code 失败"
        exit 1
      }
    }
  fi
  ok "Claude Code 安装完成"
  save_state "claude-code" "installed"
fi

ensure_workspace "$DEEPSEEK_KEY" "$ANTHROPIC_KEY"

step "验证命令"
for cmd in "node -v" "npm -v" "python3 --version" "claude --version"; do
  if bash -lc "$cmd" >> "$LOG_FILE" 2>&1; then
    ok "$cmd"
  else
    warn "$cmd 验证失败，请重开终端后再试"
  fi
done

printf '\n'
ok "安装流程完成。请重新打开终端，然后输入: claude"
printf '默认工作区: %s\n' "$WORKSPACE"
printf '如需测试 DeepSeek: cd "%s"; python3 deepseek_smoke_test.py\n\n' "$WORKSPACE"

# 安装完成后进入 DeepSeek 多轮对话模式
printf '\n\033[36m━━━ DeepSeek 助手（输入问题回车发送，直接回车退出）━━━\033[0m\n'
while true; do
  printf '\n\033[36m你: \033[0m'
  local_question=""
  read -r local_question || break
  if [[ -z "$local_question" ]]; then
    break
  fi
  local log_tail
  log_tail="$(tail -10 "$LOG_FILE" 2>/dev/null || echo "")"
  deepseek_ask "$local_question" "最近日志:\n$log_tail"
done
printf '\n\033[32m祝你使用愉快！\033[0m\n'
