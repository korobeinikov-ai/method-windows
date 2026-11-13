# Проверка установки на Windows. Запускать после install.ps1 (в проверке на GitHub — после установки с чистой машины).
# Печатает ✅/❌ по шагам, при провале выходит с ненулевым кодом. Значения ключей не печатает: только имена и пути.
# Файл без BOM: в проверке на GitHub BOM добавляется перед запуском, чтобы Windows PowerShell 5.1 не ломал русские буквы.
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { Write-Host '⚠️ Кодировка окна не переключилась: русские буквы могут выглядеть странно.' }

$script:fail = 0
function Pass($name) { Write-Host "✅ $name" }
function Fail($name, $why) {
    Write-Host "❌ $name"
    if ($why) { Write-Host "   $why" }
    $script:fail++
}
function Check($name, [scriptblock]$test) {
    $why = ''
    $ok = $false
    try { $ok = [bool](& $test) } catch { $why = $_.Exception.Message }
    if ($ok) { Pass $name } else { Fail $name $why }
}

# Как новый сеанс после перезапуска приложения Claude: пути берутся из системы, а не из старого окна
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

$homeDir = $env:USERPROFILE
$settingsPath = Join-Path $homeDir '.claude\settings.json'
$bash = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User')

# --- настройки охраны ---------------------------------------------------------------------
$script:settings = $null
Check 'Настройки Claude: файл settings.json есть и читается' {
    $script:settings = Get-Content -Raw -Encoding UTF8 -Path $settingsPath | ConvertFrom-Json
    $null -ne $script:settings
}
Check 'Охрана: в настройках Claude выключен PowerShell-инструмент (CLAUDE_CODE_USE_POWERSHELL_TOOL=0)' {
    $script:settings.env.CLAUDE_CODE_USE_POWERSHELL_TOOL -eq '0'
}
Check 'Кодировка: в настройках Claude PYTHONUTF8=1' { $script:settings.env.PYTHONUTF8 -eq '1' }
Check 'Git Bash: в настройках Claude указан путь к bash.exe, и файл на месте' {
    $b = $script:settings.env.CLAUDE_CODE_GIT_BASH_PATH
    [bool]$b -and (Test-Path $b) -and ((Split-Path $b -Leaf) -eq 'bash.exe')
}
Check 'Windows: те же три настройки записаны переменными пользователя' {
    ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_USE_POWERSHELL_TOOL', 'User') -eq '0') -and
    ([Environment]::GetEnvironmentVariable('PYTHONUTF8', 'User') -eq '1') -and
    [bool]$bash -and (Test-Path $bash)
}

# --- Git Bash и то, что сторожам нужно внутри него -------------------------------------------
Check 'Git Bash запускается и считает' {
    $o = & $bash -c 'echo ok-$((20+22))' 2>&1 | Out-String
    $o.Trim() -eq 'ok-42'
}
Check 'Git виден из Git Bash' {
    $global:LASTEXITCODE = 1
    $o = & $bash -c 'command -v git' 2>&1 | Out-String
    ($LASTEXITCODE -eq 0) -and ($o.Trim() -ne '')
}
Check 'Python виден из Git Bash и настоящий (печатает 42)' {
    $cmd = "python -c 'print(6*7)'"
    $o = & $bash -c $cmd 2>&1 | Out-String
    $o.Trim() -eq '42'
}

# --- Git, Python, Claude из обычного окна -----------------------------------------------------
Check 'Git: команда git работает' {
    $o = & git --version 2>&1 | Out-String
    $o -match 'git version \d+'
}
Check 'Python: команда python ведёт не в заглушку магазина Microsoft' {
    $c = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1
    [bool]$c -and ($c.Source -notmatch 'WindowsApps')
}
Check 'Python: настоящий, 3.9 и новее (проверено запуском, а не наличием файла)' {
    $o = & python -c "import sys; print('ok' if sys.version_info >= (3, 9) else 'old')" 2>&1 | Out-String
    $o.Trim() -eq 'ok'
}
Check 'Claude: команда claude находится и печатает версию' {
    $o = & claude --version 2>&1 | Out-String
    $o -match '\d+\.\d+\.\d+'
}
Check 'Claude: папка .local\bin стоит в путях поиска пользователя ровно один раз' {
    $bin = Join-Path $homeDir '.local\bin'
    $n = @(([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') | Where-Object { $_.Trim().TrimEnd('\') -ieq $bin }).Count
    $n -eq 1
}
Check 'Папка vibecoding в домашней папке есть' { Test-Path (Join-Path $homeDir 'vibecoding') }
Check 'Пакет метода: osnova@korobeinikov-ai-windows стоит в Claude' {
    $o = & claude plugin list 2>&1 | Out-String
    $o -match 'osnova@korobeinikov-ai-windows'
}

# --- тексты установки: ссылки на эту версию, ничего от чужой --------------------------------
$root = Split-Path -Parent $PSScriptRoot
Check 'README: первая строка про версию для Windows на месте' {
    $first = Get-Content -Path (Join-Path $root 'README.md') -Encoding UTF8 -TotalCount 1
    $first.StartsWith('> Версия для Windows.') -and $first.Contains('11.11.2026')
}
Check 'README: фраза ведёт к инструкции этой версии, инструкция — к install.ps1 этой версии' {
    ((Get-Content -Raw -Encoding UTF8 -Path (Join-Path $root 'README.md')) -match 'https://raw\.githubusercontent\.com/korobeinikov-ai/method-windows/main/CLAUDE\.md') -and
    ((Get-Content -Raw -Encoding UTF8 -Path (Join-Path $root 'CLAUDE.md')) -match 'irm https://raw\.githubusercontent\.com/korobeinikov-ai/method-windows/main/install\.ps1 \| iex')
}
Check 'Полка: marketplace.json называется korobeinikov-ai-windows' {
    $mp = Get-Content -Raw -Encoding UTF8 -Path (Join-Path $root '.claude-plugin\marketplace.json') | ConvertFrom-Json
    ($mp.name -eq 'korobeinikov-ai-windows') -and ($mp.plugins[0].name -eq 'osnova')
}
Check 'Тексты установки: нет следов установки Mac (brew, xcode, install.sh, полка Mac) и чужих путей; Mac — только ссылка на его инструкцию' {
    $bad = 'brew|xcode|install\.sh|korobeinikov-ai-method|korobeinikov-ai/method(?!-windows|/main/CLAUDE\.md)|/Users/[A-Za-z]'
    $hits = @()
    foreach ($f in 'README.md', 'CLAUDE.md', 'install.ps1', '.claude-plugin\marketplace.json') {
        if ((Get-Content -Raw -Encoding UTF8 -Path (Join-Path $root $f)) -match $bad) { $hits += $f }
    }
    if ($hits.Count -gt 0) { throw ('следы чужой версии в: ' + ($hits -join ', ')) }
    $true
}

# --- слияние настроек Claude: чужое остаётся, наше дописывается --------------------------------
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'install.ps1'
if (-not (Test-Path $installer)) {
    Fail 'install.ps1 найден рядом с тестами' $installer
} else {
    $src = [IO.File]::ReadAllText($installer, [Text.Encoding]::UTF8)
    $m = [regex]::Match($src, "(?s)PyMerge = @'\r?\n(.*?)\r?\n'@")
    if (-not $m.Success) {
        Fail 'В install.ps1 найден кусок, который дописывает настройки Claude' ''
    } else {
        $fix = Join-Path ([IO.Path]::GetTempPath()) ('metod-test-' + [Guid]::NewGuid().ToString('N'))
        $saveProfile = $env:USERPROFILE
        $saveHome = $env:HOME
        try {
            New-Item -ItemType Directory -Force -Path (Join-Path $fix '.claude') | Out-Null
            $file = Join-Path $fix '.claude\settings.json'
            $noBom = New-Object System.Text.UTF8Encoding $false
            $existing = '{"model": "opus", "permissions": {"allow": ["Bash(ls:*)"]}, "env": {"MY_OWN": "1", "PYTHONUTF8": "0"}}'
            [IO.File]::WriteAllText($file, $existing, $noBom)
            $mergePy = Join-Path $fix 'merge.py'
            Set-Content -Path $mergePy -Value $m.Groups[1].Value -Encoding ASCII
            $env:USERPROFILE = $fix
            $env:HOME = $fix
            $env:METHOD_BASH = $bash
            $global:LASTEXITCODE = 1
            $out1 = & python -I $mergePy 2>&1 | Out-String
            $rc1 = $LASTEXITCODE
            $afterFirst = (Get-FileHash $file -Algorithm SHA256).Hash
            $out2 = & python -I $mergePy 2>&1 | Out-String
            $rc2 = $LASTEXITCODE
            $merged = Get-Content -Raw -Encoding UTF8 -Path $file | ConvertFrom-Json
            $backup = Join-Path $fix '.claude\settings.json.bak-metod'
            Check 'Слияние настроек: сработало без ошибок' { ($rc1 -eq 0) -and ($rc2 -eq 0) }
            Check 'Слияние настроек: чужие ключи (model, permissions, свои env) остались' {
                ($merged.model -eq 'opus') -and ($merged.permissions.allow[0] -eq 'Bash(ls:*)') -and ($merged.env.MY_OWN -eq '1')
            }
            Check 'Слияние настроек: наши три настройки дописаны (старое значение PYTHONUTF8 исправлено)' {
                ($merged.env.CLAUDE_CODE_USE_POWERSHELL_TOOL -eq '0') -and ($merged.env.PYTHONUTF8 -eq '1') -and ($merged.env.CLAUDE_CODE_GIT_BASH_PATH -eq $bash)
            }
            Check 'Слияние настроек: копия прежнего файла сохранена' {
                (Test-Path $backup) -and ((Get-Content -Raw -Encoding UTF8 -Path $backup).Trim() -eq $existing)
            }
            Check 'Слияние настроек: второй запуск ничего не меняет' {
                ($out2.Trim() -eq 'unchanged') -and ((Get-FileHash $file -Algorithm SHA256).Hash -eq $afterFirst)
            }
            # Сломанный файл настроек не затираем
            $broken = '{ "model": "opus", '
            [IO.File]::WriteAllText($file, $broken, $noBom)
            $global:LASTEXITCODE = 0
            $null = & python -I $mergePy 2>&1
            $rc3 = $LASTEXITCODE
            Check 'Слияние настроек: сломанный файл не затирается, установка сообщает об ошибке' {
                ($rc3 -ne 0) -and ([IO.File]::ReadAllText($file) -eq $broken)
            }
        } finally {
            $env:USERPROFILE = $saveProfile
            if ($null -eq $saveHome) { Remove-Item Env:HOME -ErrorAction SilentlyContinue } else { $env:HOME = $saveHome }
            Remove-Item Env:METHOD_BASH -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force $fix -ErrorAction SilentlyContinue
        }
    }

    # --- повторный запуск install.ps1 ---------------------------------------------------------
    $settingsBefore = (Get-FileHash $settingsPath -Algorithm SHA256).Hash
    $pathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
    # Свои настройки Git человека установка не трогает: ставим метку и смотрим, что она осталась
    $crlfBefore = (& git config --global --get core.autocrlf 2>&1 | Out-String).Trim()
    & git config --global core.autocrlf input
    $env:METHOD_NO_LAUNCH = '1'
    $code = "Get-Content -Raw -Encoding UTF8 -Path '$installer' | Invoke-Expression; exit `$LASTEXITCODE"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -Command $code 2>&1 | Out-String
    $rc = $LASTEXITCODE
    $crlfAfter = (& git config --global --get core.autocrlf 2>&1 | Out-String).Trim()
    if ($crlfBefore) { & git config --global core.autocrlf $crlfBefore } else { & git config --global --unset core.autocrlf }
    Check 'Повторный запуск: свои настройки Git (концы строк) не изменены' { $crlfAfter -eq 'input' }
    Check 'Повторный запуск (Windows PowerShell 5.1): завершился без ошибок' { ($rc -eq 0) -and ($out -notmatch '❌') -and ($out -match 'Подготовка закончена') }
    Check 'Повторный запуск: настройки Claude не изменились' { (Get-FileHash $settingsPath -Algorithm SHA256).Hash -eq $settingsBefore }
    Check 'Повторный запуск: пути поиска не задублировались' { [Environment]::GetEnvironmentVariable('Path', 'User') -eq $pathBefore }
    Check 'Повторный запуск: пакет метода по-прежнему в списке Claude' {
        $o = & claude plugin list 2>&1 | Out-String
        $o -match 'osnova@korobeinikov-ai-windows'
    }

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pwsh) {
        $out7 = & $pwsh.Source -NoProfile -Command $code 2>&1 | Out-String
        $rc7 = $LASTEXITCODE
        Check 'Повторный запуск (PowerShell 7): завершился без ошибок' { ($rc7 -eq 0) -and ($out7 -notmatch '❌') -and ($out7 -match 'Подготовка закончена') }
    } else {
        Write-Host '⚠️ PowerShell 7 не установлен: проверка на нём пропущена.'
    }
}

Write-Host ''
if ($script:fail -gt 0) {
    Write-Host "❌ Установка: провалено проверок: $($script:fail)"
    exit 1
}
Write-Host '✅ Установка: все проверки пройдены'
exit 0
