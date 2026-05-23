param(
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$SkipOptional,
    [string]$DeepSeekApiKey
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$AppName = "Claude + DeepSeek Setup"
$Workspace = Join-Path $HOME "ClaudeDeepSeekWorkspace"
$StateDir = Join-Path $HOME ".claude-deepseek-setup"
$LogFile = Join-Path $StateDir "setup.log"
$StateFile = Join-Path $StateDir "state.json"
$DeepSeekBaseUrl = "https://api.deepseek.com"
$NpmRegistries = @(
    "https://registry.npmmirror.com",
    "https://registry.npmjs.org"
)
$PipIndexes = @(
    "https://pypi.tuna.tsinghua.edu.cn/simple",
    "https://mirrors.aliyun.com/pypi/simple",
    "https://repo.huaweicloud.com/repository/pypi/simple",
    "https://pypi.org/simple"
)

function Write-Step($Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format s)] STEP $Message"
}

function Write-Ok($Message) {
    Write-Host "OK  $Message" -ForegroundColor Green
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format s)] OK $Message"
}

function Write-Warn($Message) {
    Write-Host "!!  $Message" -ForegroundColor Yellow
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format s)] WARN $Message"
}

function Write-Fail($Message) {
    Write-Host "XX  $Message" -ForegroundColor Red
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format s)] FAIL $Message"
}

function Invoke-Logged($Command, [switch]$AllowFailure) {
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format s)] RUN $Command"
    if ($DryRun) {
        Write-Host "DRY $Command" -ForegroundColor DarkGray
        return $true
    }
    try {
        $global:LASTEXITCODE = 0
        $output = Invoke-Expression $Command 2>&1
        $output | ForEach-Object { Add-Content -Path $LogFile -Value $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $Command"
        }
        return $true
    } catch {
        Add-Content -Path $LogFile -Value $_
        if ($AllowFailure) { return $false }
        throw
    }
}

function Test-Command($Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = @($machinePath, $userPath) -join ";"
    Write-Ok "已刷新当前终端 PATH"
}

function Confirm-Step($Question, $DefaultYes = $true) {
    if ($Yes) { return $true }
    $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    $answer = Read-Host "$Question $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
    return $answer.Trim().ToLowerInvariant().StartsWith("y")
}

function Get-MaskedValue($Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "<empty>" }
    if ($Value.Length -le 8) { return "********" }
    return "$($Value.Substring(0, 4))...$($Value.Substring($Value.Length - 4))"
}

function Save-State($Name, $Status) {
    $state = @{}
    if (Test-Path $StateFile) {
        try {
            $json = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
            $json.PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value }
        } catch {
            $state = @{}
        }
    }
    $state[$Name] = @{
        status = $Status
        at = (Get-Date -Format s)
    }
    if (-not $DryRun) {
        $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StateFile -Encoding UTF8
    }
}

function Install-WinGetPackage($Id, $DisplayName) {
    Write-Step "检测 $DisplayName"
    $already = winget list --id $Id --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $already -match [regex]::Escape($Id)) {
        Write-Ok "$DisplayName 已安装"
        Save-State $Id "present"
        return
    }

    Write-Step "安装 $DisplayName"
    $cmd = "winget install --id $Id --exact --accept-package-agreements --accept-source-agreements"
    $null = Invoke-Logged $cmd
    Save-State $Id "installed"
}

function Set-UserEnv($Name, $Value) {
    $current = [Environment]::GetEnvironmentVariable($Name, "User")
    if ([string]::IsNullOrWhiteSpace($current)) {
        $current = [Environment]::GetEnvironmentVariable($Name, "Process")
    }

    if (-not [string]::IsNullOrWhiteSpace($current)) {
        Write-Warn "$Name 已配置为 $(Get-MaskedValue $current)"
        if ([string]::IsNullOrWhiteSpace($Value)) {
            Write-Ok "未输入新值，保留现有 $Name"
            Save-State "env:$Name" "kept"
            return
        }
        if (-not (Confirm-Step "是否覆盖 $Name？" $false)) {
            Write-Ok "保留现有 $Name"
            Save-State "env:$Name" "kept"
            return
        }
    }

    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    Write-Step "写入用户环境变量 $Name"
    if ($DryRun) {
        Write-Host "DRY setx $Name ***" -ForegroundColor DarkGray
        return
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "Env:$Name" -Value $Value
    Save-State "env:$Name" "set"
}

function Configure-ToolMirrors {
    Write-Step "配置国内镜像源"

    if (Test-Command npm) {
        foreach ($registry in $NpmRegistries) {
            $ok = Invoke-Logged "npm config set registry $registry" -AllowFailure
            if ($ok) {
                Write-Ok "npm 镜像已设置为 $registry"
                Save-State "mirror:npm" $registry
                break
            }
        }
    } else {
        Write-Warn "未检测到 npm，稍后安装 Node.js 后会在 Claude Code 安装前再次尝试"
    }

    if (Test-Command python) {
        foreach ($index in $PipIndexes) {
            $ok = Invoke-Logged "python -m pip config set global.index-url $index" -AllowFailure
            if ($ok) {
                Write-Ok "pip 镜像已设置为 $index"
                Save-State "mirror:pip" $index
                break
            }
        }
    } else {
        Write-Warn "未检测到 python，跳过 pip 镜像配置"
    }
}

# ── DeepSeek AI 助手集成 ────────────────────────────────────────────────────────
function Invoke-DeepSeekAsk($Question, $Context) {
    $key = $deepSeekKey
    if ([string]::IsNullOrWhiteSpace($key)) {
        $key = [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY", "User")
    }
    if ([string]::IsNullOrWhiteSpace($key)) {
        Write-Host "    (未配置 DeepSeek Key，无法调用 AI 助手)" -ForegroundColor DarkGray
        return
    }

    $systemContent = "你是面向电脑小白的安装助手。用简体中文回答。给出最多3个具体下一步。先解释错误含义，再给修复方案。给出的命令要说明在哪里运行。"
    $userContent = "当前环境:`nWindows $([System.Environment]::OSVersion.Version)`nNode: $(if(Test-Command node){'已安装'}else{'未安装'})`nnpm: $(if(Test-Command npm){'已安装'}else{'未安装'})`nPython: $(if(Test-Command python){'已安装'}else{'未安装'})`nClaude: $(if(Test-Command claude){'已安装'}else{'未安装'})`n`n$Context`n`n用户问题:`n$Question"

    $body = @{
        model = "deepseek-v4-flash"
        messages = @(
            @{ role = "system"; content = $systemContent },
            @{ role = "user"; content = $userContent }
        )
        stream = $false
        temperature = 0.2
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri "$DeepSeekBaseUrl/chat/completions" `
            -Method Post `
            -Headers @{ "Authorization" = "Bearer $key"; "Content-Type" = "application/json" } `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -TimeoutSec 30

        $answer = $response.choices[0].message.content
        Write-Host ""
        Write-Host "┌─ DeepSeek 助手 ─────────────────────────────────────────┐" -ForegroundColor Magenta
        $answer -split "`n" | ForEach-Object { Write-Host "│ $_" -ForegroundColor White }
        Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Magenta
        Write-Host ""
    } catch {
        Write-Host "    (DeepSeek 请求失败: $_)" -ForegroundColor DarkGray
    }
}

function Invoke-DeepSeekDiagnose($StepName, $ErrorDetail) {
    Write-Host ""
    Write-Host "    正在请求 DeepSeek 分析错误原因..." -ForegroundColor Yellow
    $logTail = ""
    if (Test-Path $LogFile) {
        $logTail = (Get-Content $LogFile -Tail 20) -join "`n"
    }
    $context = "最近日志:`n$logTail`n`n额外错误信息:`n$ErrorDetail"
    Invoke-DeepSeekAsk "安装步骤「$StepName」失败了，请分析原因并告诉我怎么修复。" $context
}

function Start-DeepSeekChat {
    Write-Host ""
    Write-Host "━━━ DeepSeek 助手（输入问题回车发送，直接回车退出）━━━" -ForegroundColor Cyan
    while ($true) {
        Write-Host ""
        $question = Read-Host "你"
        if ([string]::IsNullOrWhiteSpace($question)) { break }
        $logTail = ""
        if (Test-Path $LogFile) { $logTail = (Get-Content $LogFile -Tail 10) -join "`n" }
        Invoke-DeepSeekAsk $question "最近日志:`n$logTail"
    }
    Write-Host ""
    Write-Host "祝你使用愉快！" -ForegroundColor Green
}

function Install-ClaudeCode {
    Write-Step "安装 Claude Code"
    if (Test-Command claude) {
        Write-Ok "Claude Code 已安装"
        if (-not (Confirm-Step "是否重新安装/覆盖 Claude Code？" $false)) {
            Save-State "claude-code" "kept"
            return
        }
    }

    if ($DryRun) {
        Write-Host "DRY npm install -g @anthropic-ai/claude-code via domestic mirror, then official fallback" -ForegroundColor DarkGray
        Save-State "claude-code" "dry-run"
        return
    }

    $installed = $false
    if (Test-Command npm) {
        foreach ($registry in $NpmRegistries) {
            Write-Step "通过 npm 镜像安装 Claude Code: $registry"
            $null = Invoke-Logged "npm config set registry $registry" -AllowFailure
            $ok = Invoke-Logged "npm install -g @anthropic-ai/claude-code --registry $registry" -AllowFailure
            if ($ok) {
                $installed = $true
                break
            }
        }
    }

    if (-not $installed) {
        Write-Warn "npm 镜像安装失败，尝试 Claude 官方安装器"
        $installer = Join-Path $env:TEMP "claude-code-install.ps1"
        try {
            Add-Content -Path $LogFile -Value "[$(Get-Date -Format s)] RUN download Claude Code installer"
            Invoke-WebRequest -Uri "https://claude.ai/install.ps1" -OutFile $installer -UseBasicParsing
            & powershell -NoProfile -ExecutionPolicy Bypass -File $installer *>> $LogFile
            if ($LASTEXITCODE -eq 0) {
                $installed = $true
            }
        } catch {
            Add-Content -Path $LogFile -Value $_
        }
    }

    if (-not $installed) {
        throw "Claude Code 安装失败。已尝试 npm 国内镜像、npm 官方源和 Claude 官方安装器。"
    }
    Save-State "claude-code" "installed"
}

function Set-WorkspaceFile($RelativePath, $Content, [switch]$Sensitive) {
    $path = Join-Path $Workspace $RelativePath
    $parent = Split-Path -Parent $path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if (Test-Path -LiteralPath $path) {
        $label = if ($Sensitive) { "$RelativePath（包含本机密钥）" } else { $RelativePath }
        Write-Warn "$label 已存在"
        if (-not (Confirm-Step "是否覆盖 $RelativePath？" $false)) {
            Write-Ok "保留 $RelativePath"
            Save-State "workspace:$RelativePath" "kept"
            return
        }
    }

    Set-Content -LiteralPath $path -Value $Content -Encoding UTF8
    Save-State "workspace:$RelativePath" "written"
}

function Get-DefaultDeepSeekSkill {
    return @"
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
7. Prefer the program's buttons first: 保存 Key, 重新检测环境, 一键启动安装, 打开工作区, 打开终端运行 Claude.
8. If something is already configured, tell the user to keep it unless they intentionally want to replace it.
9. For risky actions such as overwriting files, changing environment variables, reinstalling tools, or deleting anything, tell the user to confirm first.
10. If network, permission, winget, npm, Python, or Claude install errors appear, ask for the exact red error text and give a small checklist.
11. 默认镜像策略是国内优先：Claude Code 先用 npm 国内镜像，npm/pip/Homebrew 也优先使用国内镜像，失败再回到官方源。

Decision Flow:
- No DeepSeek key: tell the user to paste the key into the top input and click 保存 Key.
- Key saved but tools missing: tell the user to click 一键启动安装.
- Install finished: tell the user to reopen terminal or click 打开终端运行 Claude.
- Claude works: tell the user they can type natural language tasks after the claude prompt appears.
- DeepSeek call fails: check key correctness, network access, quota/balance, and API endpoint.
- User is lost: summarize current environment in plain words, then give only the next button to click.

Answer Format:
第一句：一句话说明当前情况。
然后：
1. 下一步
2. 如果失败，复制哪段报错
3. 成功后会看到什么
"@
}

function Ensure-Workspace($DeepSeekKey) {
    Write-Step "创建默认工作区"
    if ($DryRun) {
        Write-Host "DRY create $Workspace" -ForegroundColor DarkGray
        return
    }

    New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Workspace "skills\deepseek-automation") | Out-Null

    $envFile = @"
DEEPSEEK_API_KEY=$DeepSeekKey
DEEPSEEK_BASE_URL=$DeepSeekBaseUrl
"@
    Set-WorkspaceFile ".env" $envFile -Sensitive

    $envExample = @"
DEEPSEEK_API_KEY=your_deepseek_api_key
DEEPSEEK_BASE_URL=https://api.deepseek.com
"@
    Set-WorkspaceFile ".env.example" $envExample

    $gitignore = @"
.env
.venv/
node_modules/
dist/
build/
__pycache__/
"@
    Set-WorkspaceFile ".gitignore" $gitignore

    $claudeMd = @"
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
- ANTHROPIC_BASE_URL
- ANTHROPIC_AUTH_TOKEN
- ANTHROPIC_MODEL
"@
    Set-WorkspaceFile "CLAUDE.md" $claudeMd

    $skill = Get-DefaultDeepSeekSkill
    Set-WorkspaceFile "skills\deepseek-automation\SKILL.md" $skill

    $python = @"
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
"@
    Set-WorkspaceFile "deepseek_smoke_test.py" $python
    Save-State "workspace" "created"
    Write-Ok "工作区已创建: $Workspace"
}

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
Add-Content -Path $LogFile -Value "[$(Get-Date -Format s)] START $AppName"

Write-Host ""
Write-Host "Claude + DeepSeek 空白电脑安装向导" -ForegroundColor Cyan
Write-Host "这个工具会检测环境、安装依赖、配置 API Key，并验证终端里的 claude 命令。"
Write-Host "💡 安装过程中如果遇到问题，DeepSeek AI 助手会自动分析并给出建议。"
Write-Host "日志: $LogFile"
Write-Host ""

$deepSeekKey = $DeepSeekApiKey
if ([string]::IsNullOrWhiteSpace($deepSeekKey)) {
    $deepSeekKey = Read-Host "请输入 DeepSeek API Key，也可以直接回车稍后再配"
}

try {
    if (-not (Test-Command winget)) {
        throw "未找到 winget。请先安装或更新 App Installer，然后重新运行本工具。"
    }
    Write-Ok "WinGet 可用"

    Install-WinGetPackage "OpenJS.NodeJS.LTS" "Node.js LTS"
    Install-WinGetPackage "Python.Python.3.12" "Python 3.12"
    Update-SessionPath
    Configure-ToolMirrors

    Set-UserEnv "DEEPSEEK_API_KEY" $deepSeekKey
    Set-UserEnv "DEEPSEEK_BASE_URL" $DeepSeekBaseUrl

    # 配置 Claude Code 使用 DeepSeek API
    Write-Step "配置 Claude Code 使用 DeepSeek"
    Set-UserEnv "ANTHROPIC_BASE_URL" "https://api.deepseek.com/anthropic"
    Set-UserEnv "ANTHROPIC_AUTH_TOKEN" $deepSeekKey
    Set-UserEnv "ANTHROPIC_MODEL" "deepseek-v4-pro"

    Install-ClaudeCode

    Ensure-Workspace $deepSeekKey

    Write-Step "验证命令"
    foreach ($cmd in @("node -v", "npm -v", "python --version", "claude --version")) {
        $ok = Invoke-Logged $cmd -AllowFailure
        if ($ok) { Write-Ok $cmd } else { Write-Warn "$cmd 验证失败，请重开终端后再试" }
    }

    Write-Host ""
    Write-Ok "安装流程完成。请重新打开终端，然后输入: claude"
    Write-Host "默认工作区: $Workspace"
    Write-Host "如需测试 DeepSeek: cd `"$Workspace`"; python deepseek_smoke_test.py"
} catch {
    Write-Fail $_
    Invoke-DeepSeekDiagnose "脚本执行" "$_"
    Write-Host ""
    Write-Host "安装没有完全完成。你可以修复上面的错误后重复运行本脚本，它会跳过已完成的部分。"
    Write-Host "日志位置: $LogFile"
    exit 1
}

# 安装完成后进入 DeepSeek 多轮对话
Start-DeepSeekChat
