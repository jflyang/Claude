# Claude + DeepSeek 空白电脑安装向导

这是一个面向 Windows 和 macOS 的轻量安装工具，用来把一台空白电脑配置到可以在终端输入 `claude` 使用 Claude Code，并准备好 DeepSeek API 环境。

它尽量只依赖系统自带能力：

- Windows: PowerShell + WinGet
- macOS: zsh/bash + Homebrew，若没有 Homebrew 会提示并安装
- Claude Code: 优先使用官方原生安装方式或平台包管理器，失败后回退到 npm 安装
- DeepSeek: 写入 `DEEPSEEK_API_KEY` 和 `DEEPSEEK_BASE_URL`
- 镜像策略: 国内优先，官方源兜底。Claude Code 优先通过 npm 国内镜像安装，npm/pip/Homebrew 默认配置国内镜像。

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

## 设计目标

- 空白电脑可用
- 跨平台
- 每一步有检测、安装、验证
- 日志和状态文件可追踪
- 可以重复运行，已安装项会跳过
- 检测到已有环境变量、Claude Code 或工作区文件时，会询问是否覆盖
- API Key 不写进仓库，只写用户环境变量和本机工作区

## 参考来源

- Claude Code 官方安装文档: https://docs.claude.com/en/docs/claude-code/setup
- Claude Code npm 包: https://www.npmjs.com/package/@anthropic-ai/claude-code
- DeepSeek API 文档: https://api-docs.deepseek.com/
