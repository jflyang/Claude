param(
    [string]$Workspace = (Join-Path $HOME "ClaudeDeepSeekWorkspace")
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$SetupScript = Join-Path $Root "claude-deepseek-setup.ps1"
$StateDir = Join-Path $HOME ".claude-deepseek-setup"
$LogFile = Join-Path $StateDir "assistant.log"
$DeepSeekBaseUrl = "https://api.deepseek.com"

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Write-AssistantLog($Message) {
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format s)] $Message"
}

function Get-MaskedValue($Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "未配置" }
    if ($Value.Length -le 8) { return "********" }
    return "$($Value.Substring(0, 4))...$($Value.Substring($Value.Length - 4))"
}

function Get-UserEnv($Name) {
    $value = [Environment]::GetEnvironmentVariable($Name, "User")
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    }
    return $value
}

function Set-UserEnvValue($Name, $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "Env:$Name" -Value $Value
}

function Test-CommandAvailable($Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function New-Label($Text, $X, $Y, $W, $H) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($W, $H)
    $label.AutoEllipsis = $true
    return $label
}

function New-Button($Text, $X, $Y, $W, $H) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($W, $H)
    return $button
}

function Get-EnvironmentSummary {
    $items = @(
        "Windows: $([Environment]::OSVersion.VersionString)"
        "DeepSeek Key: $(Get-MaskedValue (Get-UserEnv 'DEEPSEEK_API_KEY'))"
        "Git: $(if (Test-CommandAvailable 'git') { '已安装' } else { '未检测到' })"
        "Node.js: $(if (Test-CommandAvailable 'node') { '已安装' } else { '未检测到' })"
        "npm: $(if (Test-CommandAvailable 'npm') { '已安装' } else { '未检测到' })"
        "Python: $(if (Test-CommandAvailable 'python') { '已安装' } else { '未检测到' })"
        "Claude: $(if (Test-CommandAvailable 'claude') { '已安装' } else { '未检测到' })"
        "镜像策略: 国内优先，官方源兜底"
        "工作区: $Workspace"
    )
    return ($items -join "`r`n")
}

function Get-DefaultDeepSeekSkill {
    return @"
# DeepSeek Setup Guide Skill

Purpose:
Guide beginners through installing and using Claude Code with DeepSeek on Windows, with minimal jargon and safe defaults.

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

function Invoke-DeepSeekHelp($ApiKey, $Question, $Context) {
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw "请先输入并保存 DeepSeek API Key。"
    }
    if ([string]::IsNullOrWhiteSpace($Question)) {
        throw "请先输入你不会的地方。"
    }

    $systemPrompt = @"
你是一个面向电脑小白的 Claude + DeepSeek 安装助手。
回答要求：
1. 用中文。
2. 每次只给 1-3 个最重要的下一步。
3. 不要假设用户懂命令行。
4. 如果用户贴了报错，先解释这是什么意思，再给修复步骤。
5. 不要要求用户暴露 API Key。

下面是你必须遵守的默认 skill：
$(Get-DefaultDeepSeekSkill)
"@

    $payload = @{
        model = "deepseek-v4-flash"
        messages = @(
            @{ role = "system"; content = $systemPrompt },
            @{ role = "user"; content = "当前环境：`n$Context`n`n用户问题：`n$Question" }
        )
        stream = $false
        temperature = 0.2
    } | ConvertTo-Json -Depth 8

    $headers = @{
        Authorization = "Bearer $ApiKey"
        "Content-Type" = "application/json"
    }

    $response = Invoke-RestMethod -Uri "$DeepSeekBaseUrl/chat/completions" -Method Post -Headers $headers -Body $payload -TimeoutSec 60
    return $response.choices[0].message.content
}

function Ensure-AssistantWorkspace($ApiKey) {
    New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Workspace "skills\deepseek-automation") | Out-Null

    $envPath = Join-Path $Workspace ".env"
    if ((Test-Path -LiteralPath $envPath) -and -not [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $envPath -Raw))) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
            ".env 已存在，是否覆盖里面的 DeepSeek 配置？",
            "确认覆盖",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    $envContent = @"
DEEPSEEK_API_KEY=$ApiKey
DEEPSEEK_BASE_URL=$DeepSeekBaseUrl
"@
    Set-Content -LiteralPath $envPath -Value $envContent -Encoding UTF8

    $claudeMdPath = Join-Path $Workspace "CLAUDE.md"
    if (-not (Test-Path -LiteralPath $claudeMdPath)) {
        $claudeMd = @"
# Claude + DeepSeek Workspace

你是这个工作区的自动化开发助手。

默认策略：
- 用户不会安装、配置、排错时，优先用清楚的中文解释下一步。
- DeepSeek API Key 从环境变量 DEEPSEEK_API_KEY 读取。
- 不要把 API Key 写进代码、日志、截图或提交记录。
- 复杂代码理解和项目修改用 Claude Code，低成本中文解释和批量文本处理可用 DeepSeek。
"@
        Set-Content -LiteralPath $claudeMdPath -Value $claudeMd -Encoding UTF8
    }

    $skillPath = Join-Path $Workspace "skills\deepseek-automation\SKILL.md"
    if (-not (Test-Path -LiteralPath $skillPath)) {
        $skill = Get-DefaultDeepSeekSkill
        Set-Content -LiteralPath $skillPath -Value $skill -Encoding UTF8
    }
}

$font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$titleFont = New-Object System.Drawing.Font("Microsoft YaHei UI", 14, [System.Drawing.FontStyle]::Bold)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Claude + DeepSeek 小白安装助手"
$form.Size = New-Object System.Drawing.Size(880, 680)
$form.MinimumSize = New-Object System.Drawing.Size(820, 620)
$form.StartPosition = "CenterScreen"
$form.Font = $font

$title = New-Label "Claude + DeepSeek 小白安装助手" 20 18 520 34
$title.Font = $titleFont
$form.Controls.Add($title)

$subtitle = New-Label "输入 DeepSeek Key 后，就可以在这里问安装、配置、报错问题，也可以一键启动环境安装。" 22 54 760 24
$form.Controls.Add($subtitle)

$keyLabel = New-Label "DeepSeek API Key" 24 96 160 24
$form.Controls.Add($keyLabel)

$keyBox = New-Object System.Windows.Forms.TextBox
$keyBox.Location = New-Object System.Drawing.Point(24, 122)
$keyBox.Size = New-Object System.Drawing.Size(610, 28)
$keyBox.UseSystemPasswordChar = $true
$keyBox.Text = Get-UserEnv "DEEPSEEK_API_KEY"
$form.Controls.Add($keyBox)

$showKey = New-Object System.Windows.Forms.CheckBox
$showKey.Text = "显示"
$showKey.Location = New-Object System.Drawing.Point(646, 124)
$showKey.Size = New-Object System.Drawing.Size(70, 24)
$showKey.Add_CheckedChanged({ $keyBox.UseSystemPasswordChar = -not $showKey.Checked })
$form.Controls.Add($showKey)

$saveButton = New-Button "保存 Key" 730 118 110 34
$form.Controls.Add($saveButton)

$statusLabel = New-Label "状态：等待输入 Key" 24 164 810 24
$form.Controls.Add($statusLabel)

$envBox = New-Object System.Windows.Forms.TextBox
$envBox.Location = New-Object System.Drawing.Point(24, 196)
$envBox.Size = New-Object System.Drawing.Size(330, 300)
$envBox.Multiline = $true
$envBox.ReadOnly = $true
$envBox.ScrollBars = "Vertical"
$envBox.Text = Get-EnvironmentSummary
$form.Controls.Add($envBox)

$questionLabel = New-Label "不会的地方直接问 DeepSeek" 380 196 300 24
$form.Controls.Add($questionLabel)

$questionBox = New-Object System.Windows.Forms.TextBox
$questionBox.Location = New-Object System.Drawing.Point(380, 224)
$questionBox.Size = New-Object System.Drawing.Size(460, 88)
$questionBox.Multiline = $true
$questionBox.ScrollBars = "Vertical"
$questionBox.Text = "我现在应该先做哪一步？"
$form.Controls.Add($questionBox)

$askButton = New-Button "问 DeepSeek" 380 318 130 32
$form.Controls.Add($askButton)

$commonButton1 = New-Button "解释当前状态" 520 318 130 32
$form.Controls.Add($commonButton1)

$commonButton2 = New-Button "我报错了" 660 318 130 32
$form.Controls.Add($commonButton2)

$answerBox = New-Object System.Windows.Forms.TextBox
$answerBox.Location = New-Object System.Drawing.Point(380, 356)
$answerBox.Size = New-Object System.Drawing.Size(460, 140)
$answerBox.Multiline = $true
$answerBox.ReadOnly = $true
$answerBox.ScrollBars = "Vertical"
$form.Controls.Add($answerBox)

$checkButton = New-Button "重新检测环境" 24 520 150 38
$form.Controls.Add($checkButton)

$setupButton = New-Button "一键启动安装" 188 520 150 38
$form.Controls.Add($setupButton)

$workspaceButton = New-Button "打开工作区" 352 520 150 38
$form.Controls.Add($workspaceButton)

$terminalButton = New-Button "打开终端运行 Claude" 516 520 170 38
$form.Controls.Add($terminalButton)

$closeButton = New-Button "关闭" 700 520 140 38
$form.Controls.Add($closeButton)

$hint = New-Label "提示：如果某一步看不懂，把报错复制到问题框，再点“问 DeepSeek”。Key 只保存在本机用户环境变量和工作区 .env。" 24 584 820 34
$form.Controls.Add($hint)

$saveButton.Add_Click({
    try {
        $key = $keyBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            [System.Windows.Forms.MessageBox]::Show("请先输入 DeepSeek API Key。", "需要 Key") | Out-Null
            return
        }

        $existing = Get-UserEnv "DEEPSEEK_API_KEY"
        if (-not [string]::IsNullOrWhiteSpace($existing) -and $existing -ne $key) {
            $choice = [System.Windows.Forms.MessageBox]::Show(
                "系统已经配置了 DeepSeek Key：$(Get-MaskedValue $existing)`r`n是否覆盖？",
                "确认覆盖",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
                $statusLabel.Text = "状态：保留原来的 DeepSeek Key"
                return
            }
        }

        Set-UserEnvValue "DEEPSEEK_API_KEY" $key
        Set-UserEnvValue "DEEPSEEK_BASE_URL" $DeepSeekBaseUrl
        Ensure-AssistantWorkspace $key
        $envBox.Text = Get-EnvironmentSummary
        $statusLabel.Text = "状态：Key 已保存，DeepSeek 可以协助你了"
    } catch {
        Write-AssistantLog $_
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "保存失败") | Out-Null
    }
})

$askButton.Add_Click({
    try {
        $askButton.Enabled = $false
        $statusLabel.Text = "状态：DeepSeek 正在思考..."
        $answerBox.Text = "正在请求 DeepSeek，请稍等..."
        [System.Windows.Forms.Application]::DoEvents()
        $answer = Invoke-DeepSeekHelp $keyBox.Text.Trim() $questionBox.Text (Get-EnvironmentSummary)
        $answerBox.Text = $answer
        $statusLabel.Text = "状态：DeepSeek 已回复"
    } catch {
        Write-AssistantLog $_
        $answerBox.Text = "请求失败：$($_.Exception.Message)`r`n`r`n请确认 Key 正确、网络可以访问 DeepSeek。"
        $statusLabel.Text = "状态：DeepSeek 请求失败"
    } finally {
        $askButton.Enabled = $true
    }
})

$commonButton1.Add_Click({
    $questionBox.Text = "请解释左侧环境检测结果，我下一步应该做什么？"
    $askButton.PerformClick()
})

$commonButton2.Add_Click({
    $questionBox.Text = "我安装时遇到报错。请告诉我应该把哪段报错复制给你，并一步步教我排查。"
    $askButton.PerformClick()
})

$checkButton.Add_Click({
    $envBox.Text = Get-EnvironmentSummary
    $statusLabel.Text = "状态：环境检测已刷新"
})

$setupButton.Add_Click({
    if (-not (Test-Path -LiteralPath $SetupScript)) {
        [System.Windows.Forms.MessageBox]::Show("找不到安装脚本：$SetupScript", "无法启动") | Out-Null
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($keyBox.Text)) {
        Set-UserEnvValue "DEEPSEEK_API_KEY" $keyBox.Text.Trim()
        Set-UserEnvValue "DEEPSEEK_BASE_URL" $DeepSeekBaseUrl
    }
    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$SetupScript`"",
        "-DeepSeekApiKey", "`"$($keyBox.Text.Trim())`""
    )
    $statusLabel.Text = "状态：已打开安装终端，请按提示继续"
})

$workspaceButton.Add_Click({
    New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
    Start-Process explorer.exe $Workspace
})

$terminalButton.Add_Click({
    New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
    Start-Process powershell.exe -ArgumentList @("-NoExit", "-Command", "cd `"$Workspace`"; claude")
})

$closeButton.Add_Click({ $form.Close() })

[void]$form.ShowDialog()
