#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SETUP_SCRIPT="$ROOT/claude-deepseek-setup.sh"
WORKSPACE="$HOME/ClaudeDeepSeekWorkspace"
STATE_DIR="$HOME/.claude-deepseek-setup"
LOG_FILE="$STATE_DIR/mac-assistant.log"
DEEPSEEK_BASE_URL="https://api.deepseek.com"

mkdir -p "$STATE_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE"
}

alert() {
  local title="$1"
  local message="$2"
  osascript -e 'display alert (item 1 of argv) message (item 2 of argv) as informational' "$title" "$message" >/dev/null
}

ask_text() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"
  osascript \
    -e 'set theResponse to display dialog (item 2 of argv) default answer (item 3 of argv) with title (item 1 of argv) buttons {"取消", "确定"} default button "确定"' \
    -e 'text returned of theResponse' \
    "$title" "$prompt" "$default_value"
}

choose_action() {
  osascript \
    -e 'set choices to {"保存 Key", "问 DeepSeek", "检测环境", "一键启动安装", "打开工作区", "打开终端运行 Claude", "退出"}' \
    -e 'choose from list choices with title "Claude + DeepSeek 小白安装助手" with prompt "请选择下一步。不会的地方可以直接问 DeepSeek。" default items {"保存 Key"}' \
    -e 'if result is false then return "退出"' \
    -e 'item 1 of result'
}

confirm() {
  local title="$1"
  local message="$2"
  osascript \
    -e 'set r to display dialog (item 2 of argv) with title (item 1 of argv) buttons {"否", "是"} default button "否"' \
    -e 'button returned of r' \
    "$title" "$message" | grep -q '^是$'
}

mask_value() {
  local value="$1"
  if [[ -z "$value" ]]; then
    printf '未配置'
  elif [[ "${#value}" -le 8 ]]; then
    printf '********'
  else
    printf '%s...%s' "${value:0:4}" "${value: -4}"
  fi
}

shell_rc() {
  local shell_name
  shell_name="$(basename "${SHELL:-zsh}")"
  if [[ "$shell_name" == "bash" ]]; then
    printf '%s/.bash_profile' "$HOME"
  else
    printf '%s/.zshrc' "$HOME"
  fi
}

read_env_from_rc() {
  local name="$1"
  local rc
  rc="$(shell_rc)"
  if [[ -f "$rc" ]]; then
    grep -E "^export $name=" "$rc" | tail -n 1 | sed -E "s/^export $name=\"?//; s/\"?$//" || true
  fi
}

current_key() {
  if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
    printf '%s' "$DEEPSEEK_API_KEY"
  else
    read_env_from_rc "DEEPSEEK_API_KEY"
  fi
}

write_env_value() {
  local name="$1"
  local value="$2"
  local rc
  rc="$(shell_rc)"
  touch "$rc"
  if grep -q "^export $name=" "$rc"; then
    perl -0pi -e "s|^export $name=.*$|export $name=\"$value\"|mg" "$rc"
  else
    printf '\nexport %s="%s"\n' "$name" "$value" >> "$rc"
  fi
  export "$name=$value"
}

default_skill() {
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

ensure_workspace() {
  local key="$1"
  mkdir -p "$WORKSPACE/skills/deepseek-automation"

  local env_path="$WORKSPACE/.env"
  if [[ -s "$env_path" ]]; then
    if ! confirm "确认覆盖" ".env 已存在，是否覆盖里面的 DeepSeek 配置？"; then
      return 0
    fi
  fi

  cat > "$env_path" <<EOF
DEEPSEEK_API_KEY=$key
DEEPSEEK_BASE_URL=$DEEPSEEK_BASE_URL
EOF

  if [[ ! -f "$WORKSPACE/CLAUDE.md" ]]; then
    cat > "$WORKSPACE/CLAUDE.md" <<'EOF'
# Claude + DeepSeek Workspace

你是这个工作区的自动化开发助手。

默认策略：
- 用户不会安装、配置、排错时，优先用清楚的中文解释下一步。
- DeepSeek API Key 从环境变量 DEEPSEEK_API_KEY 读取。
- 不要把 API Key 写进代码、日志、截图或提交记录。
- 复杂代码理解和项目修改用 Claude Code，低成本中文解释和批量文本处理可用 DeepSeek。
EOF
  fi

  default_skill > "$WORKSPACE/skills/deepseek-automation/SKILL.md"
}

environment_summary() {
  {
    printf 'macOS: '
    sw_vers -productVersion 2>/dev/null || true
    printf 'DeepSeek Key: %s\n' "$(mask_value "$(current_key)")"
    printf 'Homebrew: %s\n' "$(command -v brew >/dev/null 2>&1 && printf '已安装' || printf '未检测到')"
    printf 'Git: %s\n' "$(command -v git >/dev/null 2>&1 && printf '已安装' || printf '未检测到')"
    printf 'Node.js: %s\n' "$(command -v node >/dev/null 2>&1 && printf '已安装' || printf '未检测到')"
    printf 'npm: %s\n' "$(command -v npm >/dev/null 2>&1 && printf '已安装' || printf '未检测到')"
    printf 'Python: %s\n' "$(command -v python3 >/dev/null 2>&1 && printf '已安装' || printf '未检测到')"
    printf 'Claude: %s\n' "$(command -v claude >/dev/null 2>&1 && printf '已安装' || printf '未检测到')"
    printf '镜像策略: 国内优先，官方源兜底\n'
    printf '工作区: %s\n' "$WORKSPACE"
  }
}

json_escape() {
  perl -MJSON::PP -0777 -ne 'print encode_json($_)'
}

ask_deepseek() {
  local key="$1"
  local question="$2"
  local context="$3"
  local skill
  skill="$(default_skill)"

  local system_json user_json payload response
  system_json="$(printf '你是一个面向电脑小白的 Claude + DeepSeek 安装助手。\n下面是你必须遵守的默认 skill：\n%s' "$skill" | json_escape)"
  user_json="$(printf '当前环境：\n%s\n\n用户问题：\n%s' "$context" "$question" | json_escape)"
  payload="{\"model\":\"deepseek-chat\",\"messages\":[{\"role\":\"system\",\"content\":$system_json},{\"role\":\"user\",\"content\":$user_json}],\"stream\":false,\"temperature\":0.2}"

  response="$(curl -sS --connect-timeout 20 --max-time 60 \
    "$DEEPSEEK_BASE_URL/chat/completions" \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -d "$payload")"

  printf '%s' "$response" | perl -MJSON::PP -0777 -ne 'my $d = decode_json($_); print $d->{choices}[0]{message}{content}' 2>/dev/null || printf '%s' "$response"
}

save_key_flow() {
  local existing key
  existing="$(current_key)"
  key="$(ask_text "保存 DeepSeek Key" "请输入 DeepSeek API Key。它只会保存在本机环境变量和工作区 .env。" "$existing")"
  [[ -z "$key" ]] && return 0

  if [[ -n "$existing" && "$existing" != "$key" ]]; then
    if ! confirm "确认覆盖" "系统已经配置了 DeepSeek Key：$(mask_value "$existing")。是否覆盖？"; then
      alert "已保留" "已保留原来的 DeepSeek Key。"
      return 0
    fi
  fi

  write_env_value "DEEPSEEK_API_KEY" "$key"
  write_env_value "DEEPSEEK_BASE_URL" "$DEEPSEEK_BASE_URL"
  ensure_workspace "$key"
  alert "保存成功" "Key 已保存。现在你可以在这个界面里问 DeepSeek，或点击一键启动安装。"
}

help_flow() {
  local key question answer
  key="$(current_key)"
  if [[ -z "$key" ]]; then
    alert "需要 Key" "请先选择“保存 Key”，输入 DeepSeek API Key。"
    return 0
  fi
  question="$(ask_text "问 DeepSeek" "把你不会的地方或报错粘贴在这里。" "我现在应该先做哪一步？")"
  [[ -z "$question" ]] && return 0
  log "ASK $question"
  answer="$(ask_deepseek "$key" "$question" "$(environment_summary)")"
  osascript -e 'display dialog (item 1 of argv) with title "DeepSeek 回复" buttons {"确定"} default button "确定"' "$answer" >/dev/null
}

setup_flow() {
  if [[ ! -f "$SETUP_SCRIPT" ]]; then
    alert "无法启动" "找不到安装脚本：$SETUP_SCRIPT"
    return 0
  fi
  chmod +x "$SETUP_SCRIPT"
  osascript -e 'tell application "Terminal" to activate' \
            -e 'tell application "Terminal" to do script quoted form of (item 1 of argv)' "$SETUP_SCRIPT"
}

open_terminal_claude() {
  mkdir -p "$WORKSPACE"
  osascript -e 'tell application "Terminal" to activate' \
            -e 'tell application "Terminal" to do script "cd " & quoted form of (item 1 of argv) & "; claude"' "$WORKSPACE"
}

main() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This assistant is for macOS. On Windows, run Start-Windows-Setup.cmd."
    exit 1
  fi

  while true; do
    action="$(choose_action)"
    case "$action" in
      "保存 Key") save_key_flow ;;
      "问 DeepSeek") help_flow ;;
      "检测环境") alert "环境检测" "$(environment_summary)" ;;
      "一键启动安装") setup_flow ;;
      "打开工作区") mkdir -p "$WORKSPACE"; open "$WORKSPACE" ;;
      "打开终端运行 Claude") open_terminal_claude ;;
      "退出") exit 0 ;;
    esac
  done
}

main "$@"
