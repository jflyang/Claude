# Claude + DeepSeek 空白电脑安装向导

这是一个面向 Windows 和 macOS 的轻量安装工具，用来把一台空白电脑配置到可以在终端输入 `claude` 使用 Claude Code，并准备好 DeepSeek API 环境。

它尽量只依赖系统自带能力：

- Windows: PowerShell + WinGet
- macOS: zsh/bash + Homebrew，若没有 Homebrew 会提示并安装
- Claude Code: 优先使用官方原生安装方式或平台包管理器，失败后回退到 npm 安装
- DeepSeek: 写入 `DEEPSEEK_API_KEY` 和 `DEEPSEEK_BASE_URL`
- 镜像策略: 国内优先，官方源兜底。Claude Code 优先通过 npm 国内镜像安装，npm/pip/Homebrew 默认配置国内镜像。

## 新特性

### 实时进度指示

命令行安装脚本现在为所有耗时操作提供实时进度反馈：

```
⠹ 正在安装 Node.js LTS... (12s)
⠼ 正在更新 Homebrew 索引... (8s)
⠧ 正在通过 npm 安装 Claude Code... (45s)
```

- 旋转动画每秒刷新，显示已耗时秒数
- 覆盖 Homebrew 安装、brew update、brew install、npm install 等所有长耗时步骤
- Homebrew 首次安装因需要 sudo 交互，直接输出到终端（可看到完整进度并输入密码）

### DeepSeek AI 助手集成（命令行版）

安装过程中遇到错误时，脚本会**自动调用 DeepSeek 分析原因并给出修复建议**：

```
XX  Node.js LTS 安装失败 (exit code: 1)

    正在请求 DeepSeek 分析错误原因...

┌─ DeepSeek 助手 ─────────────────────────────────────────┐
│ 当前情况：brew install node 失败，可能是网络超时。
│
│ 1. 检查网络连接，尝试: brew install node
│ 2. 如果超时，设置代理: export https_proxy=...
│ 3. 成功后会看到: OK Node.js LTS 安装完成
└────────────────────────────────────────────────────────────┘
```

- 每个安装步骤失败时自动触发 DeepSeek 诊断
- 基于当前环境信息和最近日志分析问题
- 用中文给出最多 3 个具体修复步骤
- 安装完成后可选择继续向 DeepSeek 提问

## 快速使用

### Windows 图形界面，推荐

双击：

```text
Start-Windows-Setup.cmd
```

界面里只需要先输入 DeepSeek API Key，然后可以：

- 保存 Key
- 重新检测环境
- 不会的地方直接问 DeepSeek
- 一键启动安装
- 打开工作区
- 打开终端运行 Claude

### Windows 命令行

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\claude-deepseek-setup.ps1
```

如果只是想预览会执行什么：

```powershell
.\claude-deepseek-setup.ps1 -DryRun
```

### macOS 图形界面，推荐

双击：

```text
Start-macOS-Setup.command
```

它会打开 macOS 原生弹窗菜单，可以保存 Key、问 DeepSeek、检测环境、一键启动安装、打开工作区、打开终端运行 Claude。

> 首次运行如果提示"无法验证开发者"，前往 **系统偏好设置 → 安全性与隐私 → 通用**，点击"仍要打开"。

### macOS 命令行

打开 Terminal，进入本目录后执行：

```bash
chmod +x ./claude-deepseek-setup.sh
./claude-deepseek-setup.sh
```

预览模式：

```bash
./claude-deepseek-setup.sh --dry-run
```

## 安装完成后

重新打开终端，执行：

```bash
claude
```

向导还会创建一个默认工作区：

```text
~/ClaudeDeepSeekWorkspace
```

里面包含：

- `.env`
- `.env.example`
- `CLAUDE.md`
- `skills/deepseek-automation/SKILL.md`
- `deepseek_smoke_test.py`

## 小白协助界面

Windows 图形界面文件是：

```text
ClaudeDeepSeekAssistant.ps1
```

macOS 图形界面文件是：

```text
ClaudeDeepSeekAssistant.command
```

它们不需要 Python 或 Node.js 作为前置条件，使用系统自带能力打开。用户输入 DeepSeek Key 后，遇到安装、配置、报错问题，可以直接在界面里问 DeepSeek。DeepSeek 会根据环境检测结果和默认 skill，用中文给下一步建议。

命令行脚本同样内置了 DeepSeek 助手，安装失败时自动调用，无需切换到图形界面。

## 设计目标

- 空白电脑可用
- 跨平台
- 每一步有检测、安装、验证
- 实时进度反馈，不再"没有反应"
- 失败时 AI 自动诊断，降低排错门槛
- 日志和状态文件可追踪
- 可以重复运行，已安装项会跳过
- 检测到已有环境变量、Claude Code 或工作区文件时，会询问是否覆盖
- API Key 不写进仓库，只写用户环境变量和本机工作区

## 参考来源

- Claude Code 官方安装文档: https://docs.claude.com/en/docs/claude-code/setup
- Claude Code npm 包: https://www.npmjs.com/package/@anthropic-ai/claude-code
- DeepSeek API 文档: https://api-docs.deepseek.com/
