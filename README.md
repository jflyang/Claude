# Claude + DeepSeek 一键安装向导

把一台 Windows 或 macOS 空白电脑，配置成可以直接在终端输入 `claude` 使用的 AI 编程环境。  
用户只需要准备一个 **DeepSeek API Key**，脚本会自动安装依赖、配置镜像、接入 DeepSeek，并在出错时调用 DeepSeek 给出中文排查建议。

## 适合谁

- 不熟悉命令行，但想用 Claude Code / DeepSeek 写代码的人
- 新电脑需要快速配置 AI 编程环境的人
- 国内网络下安装 Node.js、Python、Claude Code 经常失败的人
- 希望一个脚本自动检测、安装、配置、验证的人

## 安装后能做什么

安装完成后，重新打开终端，输入：

```bash
claude
```

之后就可以直接用中文描述任务，例如：

```text
帮我新建一个 Python 自动化脚本，读取 Excel 并生成汇总报告。
```

## 你需要准备

| 项目 | 说明 |
|---|---|
| DeepSeek API Key | 访问 [DeepSeek Platform](https://platform.deepseek.com/) 创建，通常以 `sk-` 开头 |
| 网络 | 能访问 GitHub、DeepSeek；脚本会优先使用国内镜像 |
| 系统 | Windows 10/11 或 macOS |

## 快速开始

### 方式 A：拖入终端运行，最适合小白

先在 GitHub 页面点击 **Code → Download ZIP**，下载后解压。

#### macOS

1. 打开 **Terminal / 终端**
2. 先输入下面 5 个字符，注意最后有一个空格：

```text
bash 
```

3. 把 `claude-deepseek-setup.sh` 文件拖进终端窗口
4. 按回车

拖进去以后会像这样，路径会自动变成你的真实位置：

```bash
bash /Users/你的名字/Downloads/Claude-main/claude-deepseek-setup.sh
```

#### Windows

1. 打开 **PowerShell**
2. 先复制下面这一整行，注意最后有一个空格：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 
```

3. 把 `claude-deepseek-setup.ps1` 文件拖进 PowerShell 窗口
4. 按回车

拖进去以后会像这样，路径会自动变成你的真实位置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\你的名字\Downloads\Claude-main\claude-deepseek-setup.ps1
```

### 方式 B：一键远程运行，适合会复制命令的人

#### macOS：打开 Terminal

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jflyang/Claude/main/claude-deepseek-setup.sh)"
```

#### Windows：打开 PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
$script = "$env:TEMP\claude-deepseek-setup.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/jflyang/Claude/main/claude-deepseek-setup.ps1" -OutFile $script -UseBasicParsing
powershell -NoProfile -ExecutionPolicy Bypass -File $script
```

### 方式 C：开发者用 Git Clone

#### macOS / Linux

```bash
git clone https://github.com/jflyang/Claude.git
cd Claude
chmod +x ./claude-deepseek-setup.sh
./claude-deepseek-setup.sh
```

#### Windows PowerShell

```powershell
git clone https://github.com/jflyang/Claude.git
cd Claude
Set-ExecutionPolicy -Scope Process Bypass -Force
.\claude-deepseek-setup.ps1
```

> 不要只复制 `.\claude-deepseek-setup.ps1` 到任意 PowerShell 窗口里运行。这个命令只有在脚本已经下载，并且终端已经进入脚本所在文件夹时才有效。

## 脚本会做什么

| 步骤 | 内容 |
|---|---|
| 1 | 检测系统、终端和已有工具 |
| 2 | 安装 Node.js，作为 Claude Code 运行环境 |
| 3 | 安装 Python，用于 DeepSeek 连通性测试 |
| 4 | 配置 npm / pip / Homebrew 国内镜像 |
| 5 | 设置 DeepSeek 和 Claude Code 环境变量 |
| 6 | 安装 Claude Code |
| 7 | 创建 `~/ClaudeDeepSeekWorkspace` 工作区 |
| 8 | 验证 `node`、`npm`、`python`、`claude` 命令 |
| 9 | 进入 DeepSeek 多轮问答，用户可以直接问问题 |

## 运行效果

### 安装过程

```text
Claude + DeepSeek 空白电脑安装向导
安装过程中如果遇到问题，DeepSeek AI 助手会自动分析并给出建议。

请输入 DeepSeek API Key: sk-xxxx...

OK  Node.js 已可用
OK  Python 已可用

==> 配置 Claude Code 使用 DeepSeek
OK  ANTHROPIC_BASE_URL 已设置
OK  ANTHROPIC_AUTH_TOKEN 已设置
OK  ANTHROPIC_MODEL 已设置

==> 安装 Claude Code
OK  Claude Code 已安装

OK  安装流程完成。请重新打开终端，然后输入: claude
```

### 失败时自动诊断

```text
XX  Node.js 安装失败

正在请求 DeepSeek 分析错误原因...

DeepSeek 助手：
当前情况：Node.js 下载可能超时。

1. 请先确认网络正常
2. 重新运行脚本，它会自动尝试国内镜像
3. 如果仍失败，请复制红色报错给我
```

### 安装后继续提问

```text
━━━ DeepSeek 助手（输入问题回车发送，直接回车退出）━━━

你: 怎么用 Claude Code？

DeepSeek 助手：
Claude Code 已经配置好了。

1. 打开终端，输入 claude 回车
2. 直接用中文描述你想做的事
3. 成功后会进入 Claude Code 对话界面
```

## DeepSeek 如何接入 Claude Code

脚本会自动设置这些环境变量，让 Claude Code 通过 DeepSeek 的 Anthropic 兼容端点工作：

| 环境变量 | 值 | 作用 |
|---|---|---|
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` | API 请求发送到 DeepSeek |
| `ANTHROPIC_AUTH_TOKEN` | 你的 DeepSeek Key | 认证 |
| `ANTHROPIC_MODEL` | `deepseek-v4-pro` | Claude Code 使用的模型 |

## 模型选择

| 场景 | 模型 | 说明 |
|---|---|---|
| Claude Code 编程 | `deepseek-v4-pro` | 更适合推理和代码任务 |
| 脚本内置助手 | `deepseek-v4-flash` | 响应更快，适合安装排错 |

## 国内镜像策略

| 工具 | 策略 |
|---|---|
| Node.js | 优先 npmmirror 安装包，失败后回退系统包管理器 |
| Claude Code | 优先 npm 国内镜像，失败后回退官方源 |
| npm | `https://registry.npmmirror.com` |
| pip | 清华源 → 阿里云 → 华为云 → 官方 |
| Homebrew | 阿里云镜像 |

## 创建的工作区

```text
~/ClaudeDeepSeekWorkspace/
├── .env
├── .env.example
├── .gitignore
├── CLAUDE.md
├── skills/deepseek-automation/
│   └── SKILL.md
└── deepseek_smoke_test.py
```

`.env` 里包含你的 API Key，不要上传到 GitHub。

## 文件说明

| 文件 | 平台 | 说明 |
|---|---|---|
| `claude-deepseek-setup.sh` | macOS | macOS 安装脚本 |
| `claude-deepseek-setup.ps1` | Windows | Windows 安装脚本 |

## 常见问题

### 复制命令后提示找不到脚本

通常是因为终端没有进入脚本所在文件夹。最简单的方法是使用上面的“拖入终端运行”。

### Windows 提示禁止运行脚本

使用 README 中的 Windows 拖入方式，它已经带了：

```powershell
-ExecutionPolicy Bypass
```

只对当前这次运行生效，不会永久修改系统策略。

### 安装过程中卡住

Node.js、Python、Claude Code 都可能需要下载文件。国内网络下脚本会优先使用镜像。  
如果一直失败，把最后几行红色报错复制给安装结束后的 DeepSeek 助手。

### API Key 会不会上传？

不会。Key 只会写入本机用户环境变量和 `~/ClaudeDeepSeekWorkspace/.env`。

## 设计原则

- 空白电脑可用
- 一个 DeepSeek Key 搞定
- 国内网络友好
- 失败自动诊断
- 可重复运行
- 不把 API Key 写进仓库

## 参考

- [DeepSeek API 文档](https://api-docs.deepseek.com/)
- [DeepSeek 接入 Claude Code 指南](https://api-docs.deepseek.com/guides/agent_integrations/claude_code)
- [Claude Code 官方文档](https://docs.claude.com/en/docs/claude-code/setup)
