#!/usr/bin/env bash
set -euo pipefail

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
HOMEBREW_BREW_GIT_REMOTE_DEFAULT="https://mirrors.ustc.edu.cn/brew.git"
HOMEBREW_CORE_GIT_REMOTE_DEFAULT="https://mirrors.ustc.edu.cn/homebrew-core.git"
HOMEBREW_API_DOMAIN_DEFAULT="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
HOMEBREW_BOTTLE_DOMAIN_DEFAULT="https://mirrors.ustc.edu.cn/homebrew-bottles"

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

confirm() {
  local question="$1"
  local default="${2:-yes}"
  if [[ "$YES" == "1" ]]; then
    return 0
  fi
  local suffix="[Y/n]"
  [[ "$default" == "no" ]] && suffix="[y/N]"
  read -r -p "$question $suffix " answer
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

  step "写入用户环境变量 $name"

  local shell_name
  shell_name="$(basename "${SHELL:-zsh}")"
  local rc="$HOME/.zshrc"
  [[ "$shell_name" == "bash" ]] && rc="$HOME/.bash_profile"

  local current="${!name:-}"
  if [[ -z "$current" && -f "$rc" ]]; then
    current="$(grep -E "^export $name=" "$rc" | tail -n 1 | sed -E "s/^export $name=\"?//; s/\"?$//" || true)"
  fi

  if [[ -n "$current" ]]; then
    warn "$name 已配置为 $(mask_value "$current")"
    if [[ -z "$value" ]]; then
      ok "未输入新值，保留现有 $name"
      save_state "env:$name" "kept"
      return 0
    fi
    if ! confirm "是否覆盖 $name？" "no"; then
      ok "保留现有 $name"
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
    [[ "$sensitive" == "yes" ]] && label="$relative_path（包含本机密钥）"
    warn "$label 已存在"
    if ! confirm "是否覆盖 $relative_path？" "no"; then
      ok "保留 $relative_path"
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
  log "RUN /bin/bash -c Homebrew official installer"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '\033[90mDRY /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\033[0m\n'
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >> "$LOG_FILE" 2>&1
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
  step "检测 $display"
  if brew list "$package" >/dev/null 2>&1 || brew list --cask "$package" >/dev/null 2>&1; then
    ok "$display 已安装"
    save_state "$package" "present"
    return
  fi

  step "安装 $display"
  if [[ "$package" == "visual-studio-code" || "$package" == "docker" || "$package" == "claude-code" ]]; then
    run brew install --cask "$package"
  else
    run brew install "$package"
  fi
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
    "model": "deepseek-chat",
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

trap 'fail "安装没有完全完成。修复错误后可重复运行，日志: $LOG_FILE"' ERR
log "START $APP_NAME"

printf '\n\033[36mClaude + DeepSeek 空白电脑安装向导\033[0m\n'
printf '这个工具会检测环境、安装依赖、配置 API Key，并验证终端里的 claude 命令。\n'
printf '日志: %s\n\n' "$LOG_FILE"

read -r -p "请输入 DeepSeek API Key，也可以直接回车稍后再配: " DEEPSEEK_KEY
read -r -p "可选：请输入 Anthropic API Key，也可以直接回车使用 Claude 登录流程: " ANTHROPIC_KEY

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "这个脚本适用于 macOS。Windows 请运行 claude-deepseek-setup.ps1"
  exit 1
fi

install_brew_if_needed
configure_mirrors
brew update || warn "brew update 失败，继续尝试安装"

brew_install git "Git"
brew_install node "Node.js LTS"
brew_install python@3.12 "Python 3.12"
brew_install visual-studio-code "VS Code"
configure_mirrors

if [[ "$SKIP_OPTIONAL" != "1" ]] && confirm "是否安装 Docker Desktop？这一步较大，但对后端/数据库/自动化测试很有用" "no"; then
  brew_install docker "Docker Desktop"
fi

append_env "DEEPSEEK_API_KEY" "$DEEPSEEK_KEY"
append_env "DEEPSEEK_BASE_URL" "$DEEPSEEK_BASE_URL"
append_env "ANTHROPIC_API_KEY" "$ANTHROPIC_KEY"

step "安装 Claude Code"
if has_cmd claude; then
  ok "Claude Code 已安装"
  if confirm "是否重新安装/覆盖 Claude Code？" "no"; then
    installed=0
    if command -v npm >/dev/null 2>&1; then
      for registry in "${NPM_REGISTRIES[@]}"; do
        try_run npm config set registry "$registry" || true
        if try_run npm install -g @anthropic-ai/claude-code --registry "$registry"; then
          installed=1
          break
        fi
      done
    fi
    if [[ "$installed" != "1" ]] && ! try_run brew install --cask claude-code; then
      warn "Claude Code 安装失败：已尝试 npm 国内镜像、npm 官方源和 Homebrew"
      exit 1
    fi
  else
    save_state "claude-code" "kept"
  fi
else
  installed=0
  if command -v npm >/dev/null 2>&1; then
    for registry in "${NPM_REGISTRIES[@]}"; do
      try_run npm config set registry "$registry" || true
      if try_run npm install -g @anthropic-ai/claude-code --registry "$registry"; then
        installed=1
        break
      fi
    done
  fi
  if [[ "$installed" != "1" ]] && ! try_run brew install --cask claude-code; then
    warn "Claude Code 安装失败：已尝试 npm 国内镜像、npm 官方源和 Homebrew"
    exit 1
  fi
  save_state "claude-code" "installed"
fi

ensure_workspace "$DEEPSEEK_KEY" "$ANTHROPIC_KEY"

step "验证命令"
for cmd in "git --version" "node -v" "npm -v" "python3 --version" "claude --version"; do
  if bash -lc "$cmd" >> "$LOG_FILE" 2>&1; then
    ok "$cmd"
  else
    warn "$cmd 验证失败，请重开终端后再试"
  fi
done

printf '\n'
ok "安装流程完成。请重新打开终端，然后输入: claude"
printf '默认工作区: %s\n' "$WORKSPACE"
printf '如需测试 DeepSeek: cd "%s"; python3 deepseek_smoke_test.py\n' "$WORKSPACE"
