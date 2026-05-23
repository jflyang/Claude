#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1

# 调整终端窗口样式：放大字体、设置窗口大小、深色背景，并固化为默认
osascript -e '
tell application "Terminal"
  set font name of settings set "Pro" to "Menlo"
  set font size of settings set "Pro" to 14
  set default settings to settings set "Pro"
  set startup settings to settings set "Pro"
  set currentTab to selected tab of front window
  set current settings of currentTab to settings set "Pro"
  tell front window
    set bounds to {60, 60, 1000, 750}
  end tell
end tell
' 2>/dev/null

chmod +x ./ClaudeDeepSeekAssistant.command
./ClaudeDeepSeekAssistant.command
