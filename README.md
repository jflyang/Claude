# Claude + DeepSeek 一键安装向导

把一台空白电脑配置到可以在终端输入 `claude` 使用 Claude Code，并自动接入 DeepSeek API。

只需要一个 DeepSeek API Key，全程自动完成。

---

## 它做了什么

```
┌─────────────────────────────────────────────────────────────┐
│  1. 安装 Node.js（Claude Code 运行环境）                      │
│  2. 安装 Python（DeepSeek 测试脚本）                          │
│  3. 配置国内镜像源（npm/pip）                                 │
│  4. 设置环境变量（DeepSeek Key → Claude Code 直接可用）        │
│  5. 安装 Claude Code                                         │
│  6. 创建工作区 ~/ClaudeDeepSeekWorkspace                      │
│  7. 进入 DeepSeek 多轮对话（有问题随时问）                     │
└─────────────────────────────────────────────────────────────┘
```

安装完成后，打开终端输入 `claude` 就能用 DeepSeek 驱动的 Claude Code 了。

---

## 快速开始

### 方式 A：拖入终端运行，最适合小白

如果你已经下载并解压了这个项目：

#### macOS

1. 打开 **Terminal / 终端**
2. 先输入下面这 5 个字符，注意最后有一个空格：

```text
bash 
```

3. 把 `claude-deepseek-setup.sh` 文件拖进终端窗口
4. 按回车

拖进去以后，看起来会像这样，路径会自动变成你的真实位置：

```bash
bash /Users/你的名字/Downloads/Claude-main/claude-deepseek-setup.sh
```

#### Windows

1. 打开 **PowerShell**
2. 先复制下面这一整行到 PowerShell，注意最后有一个空格：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 
```

3. 把 `claude-deepseek-setup.ps1` 文件拖进 PowerShell 窗口
4. 按回车

拖进去以后，看起来会像这样，路径会自动变成你的真实位置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\你的名字\Downloads\Claude-main\claude-deepseek-setup.ps1
```

### 方式 B：一键远程运行，推荐给会复制命令的人

打开系统自带终端，复制整段命令运行。

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

> 不要只复制 `.\claude-deepseek-setup.ps1`。这个命令只有在脚本已经下载、并且终端已经进入脚本所在文件夹时才有效。

### 方式 C：下载 ZIP 后手动运行

如果你是在 GitHub 页面点 **Code → Download ZIP** 下载的：

1. 解压 ZIP
2. 打开解压后的 `Claude-main` 文件夹
3. 在文件夹空白处打开终端
4. 按系统复制下面命令

#### macOS

```bash
chmod +x ./claude-deepseek-setup.sh
./claude-deepseek-setup.sh
```

#### Windows PowerShell

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\claude-deepseek-setup.ps1
```

### 方式 D：开发者用 Git Clone

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

---

## 运行效果

### 终端自动美化

脚本启动时自动切换为深色主题 + 14号字体，固化为默认设置：

```
==> 正在优化终端显示效果...
OK  已切换为深色主题、14号字体，并设为默认
```

### 安装过程（一路回车即可）

```
Claude + DeepSeek 空白电脑安装向导
💡 安装过程中如果遇到问题，DeepSeek AI 助手会自动分析并给出建议。

请输入 DeepSeek API Key: sk-xxxx...

OK  Homebrew 可用
OK  Node.js 已可用 (v22.15.0)
系统已有 Node.js，是否跳过？ [Y/n] y
OK  Python 已可用 (Python 3.11.5)
系统已有 Python，是否跳过？ [Y/n] y

==> 配置 Claude Code 使用 DeepSeek
OK  ANTHROPIC_BASE_URL 已设置
OK  ANTHROPIC_AUTH_TOKEN 已设置
OK  ANTHROPIC_MODEL 已设置

==> 安装 Claude Code
OK  Claude Code 已安装 (2.1.150)

==> 验证命令
OK  node -v
OK  npm -v
OK  python3 --version
OK  claude --version

OK  安装流程完成。请重新打开终端，然后输入: claude
```

### 失败时 DeepSeek 自动诊断

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

### 安装后多轮对话

```
━━━ DeepSeek 助手（输入问题回车发送，直接回车退出）━━━

你: 怎么用 Claude Code？

┌─ DeepSeek 助手 ─────────────────────────────────────────┐
│ Claude Code 已经配置好了。
│
│ 1. 打开终端，输入 claude 回车
│ 2. 直接用中文描述你想做的事
│ 3. 比如："帮我写一个 Python 爬虫"
└────────────────────────────────────────────────────────────┘

你: (直接回车退出)

祝你使用愉快！
```

---

## 技术细节

### Claude Code 如何使用 DeepSeek

脚本自动配置以下环境变量，让 Claude Code 通过 DeepSeek 的 Anthropic 兼容端点工作：

| 环境变量 | 值 | 作用 |
|---------|-----|------|
| `ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` | API 请求发到 DeepSeek |
| `ANTHROPIC_AUTH_TOKEN` | 你的 DeepSeek Key | 认证 |
| `ANTHROPIC_MODEL` | `deepseek-v4-pro` | 使用 DeepSeek V4 Pro |

### 模型选择

| 场景 | 模型 | 说明 |
|------|------|------|
| Claude Code 干活 | `deepseek-v4-pro` | 更强的推理和代码能力 |
| 脚本内置 AI 助手 | `deepseek-v4-flash` | 快速响应、低成本 |

### 镜像策略

- Node.js：优先从 npmmirror（淘宝源）下载 .pkg 安装包
- npm：`https://registry.npmmirror.com`
- pip：清华源 → 阿里云 → 华为云 → 官方
- Homebrew：阿里云镜像

### 创建的工作区

```
~/ClaudeDeepSeekWorkspace/
├── .env                              # DeepSeek Key（不提交 Git）
├── .env.example                      # 示例
├── .gitignore
├── CLAUDE.md                         # Claude Code 工作区配置
├── skills/deepseek-automation/
│   └── SKILL.md                      # DeepSeek 助手 Skill
└── deepseek_smoke_test.py            # 验证 DeepSeek API 连通性
```

---

## 文件说明

| 文件 | 平台 | 说明 |
|------|------|------|
| `claude-deepseek-setup.sh` | macOS | 安装脚本 |
| `claude-deepseek-setup.ps1` | Windows | 安装脚本 |

---

## 设计原则

- **空白电脑可用** — 不依赖预装开发工具
- **一个 Key 搞定** — 只需 DeepSeek API Key，无需 Anthropic 账号
- **国内网络友好** — 所有下载优先走国内镜像
- **失败有兜底** — AI 自动诊断错误，给出修复建议
- **可重复运行** — 已安装的会跳过，不会重复操作
- **不污染仓库** — API Key 只写入本机环境变量和工作区 .env

---

## 获取 DeepSeek API Key

1. 访问 https://platform.deepseek.com/
2. 注册/登录
3. 进入 API Keys 页面，创建新 Key
4. 复制 Key（以 `sk-` 开头）

---

## 参考

- [DeepSeek API 文档](https://api-docs.deepseek.com/)
- [DeepSeek 接入 Claude Code 官方指南](https://api-docs.deepseek.com/guides/agent_integrations/claude_code)
- [Claude Code 官方文档](https://docs.claude.com/en/docs/claude-code/setup)
