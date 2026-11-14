# Подготовка Windows для метода KOROBEINIKOV AI одной строкой:
#   irm https://raw.githubusercontent.com/korobeinikov-ai/method-windows/main/install.ps1 | iex
# Обычно её запускает сам Claude в приложении Claude (вкладка Code) по инструкции CLAUDE.md: тогда Claude уже есть
# (его путь — в CLAUDE_CODE_EXECPATH), строка его не ставит и не запускает. Из обычного окна PowerShell она работает
# так же и в конце запускает Claude сама. В строке нет кавычек: мессенджеры подменяют их на «ёлочки».
# Ставит Git и Python (для текущего пользователя, администратор не нужен), включает настройки охраны ключей,
# подключает пакет метода и строку над полем ввода приложения.
# Повторный запуск безопасен: что уже стоит, не трогает; чужие настройки только дописывает.
# Файл без BOM и с переводами строк LF: так его читает и `irm | iex` в Windows PowerShell 5.1, и PowerShell 7.
# Всё внутри одного блока: оборвётся скачивание — не выполнится половина, а окно человека не засоряется функциями.
# Изнутри Claude ещё подключает личный доступ (METHOD_DOSTUP — ссылка из бота), ставит программы пакета, проверяет охрану
# и печатает пути проводника: знакомство и проект Claude ведёт в том же чате (инструкция CLAUDE.md).
# Переменные только для проверок (человеку не видны):
#   METHOD_LOCAL_DIR — взять пакет метода из этой папки, а не с GitHub (так проверяет CI);
#   METHOD_NO_LAUNCH — всё поставить, но Claude не запускать;
#   METHOD_BEZ_WINGET — ставить Git и Python так, будто winget нет (запасной путь).
& {
    $ErrorActionPreference = 'Continue'
    $ProgressPreference = 'SilentlyContinue'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { Write-Host '⚠️ Не смог включить TLS 1.2, продолжаю.' }
    # Русские буквы и значки в этом окне: без этого вывод программ может превратиться в «кракозябры».
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { Write-Host '⚠️ Не смог переключить кодировку окна: русские буквы могут выглядеть странно, на установку это не влияет.' }

    $S = @{
        Repo   = 'korobeinikov-ai/method-windows'
        Polka  = 'korobeinikov-ai-windows'
        Stroka = 'irm https://raw.githubusercontent.com/korobeinikov-ai/method-windows/main/install.ps1 | iex'
        Fraza  = 'Начнём'
        Home   = $env:USERPROFILE
        Local  = $env:METHOD_LOCAL_DIR
        NoRun  = [bool]$env:METHOD_NO_LAUNCH
        # Запущены изнутри Claude (приложение или терминал): ставить и запускать Claude не нужно
        Vnutri = [bool]($env:CLAUDE_CODE_EXECPATH -and (Test-Path -LiteralPath $env:CLAUDE_CODE_EXECPATH))
    }
    if ($S.Vnutri) { $S.NoRun = $true }
    $S.Paket = 'osnova@' + $S.Polka
    $S.Bin = Join-Path $S.Home '.local\bin'
    $S.Work = Join-Path $S.Home 'vibecoding'

    function Say($text) { Write-Host $text }

    # Как запустить снова. Изнутри Claude это читает Claude: человеку команд не показываем.
    function Say-Again {
        if ($S.Vnutri) {
            Write-Host 'ДЛЯ CLAUDE: почини сам и запусти подготовку ещё раз той же командой — что уже стоит, она не тронет. Человеку команд не показывай.'
            Write-Host 'ИТОГ: ❌ подготовка остановилась на строке выше.'
            return
        }
        Write-Host 'Потом нажмите стрелку вверх и Enter или вставьте эту строку ещё раз. Что уже поставилось, она не тронет:'
        Write-Host "  $($S.Stroka)"
        Write-Host ''
        Write-Host 'Снова не вышло — пришлите автору текст с экрана там, где вы с ним общаетесь.'
    }

    # Остановка: что случилось, что делать и как запустить снова.
    function Stop-Install($what, $do) {
        Write-Host ''
        Write-Host "❌ $what" -ForegroundColor Red
        Write-Host "Что делать: $do"
        Write-Host ''
        Say-Again
        throw 'METHOD_STOP'
    }

    # --- пути поиска программ -------------------------------------------------------------
    function Norm($p) { ([Environment]::ExpandEnvironmentVariables($p)).Trim().TrimEnd('\').ToLowerInvariant() }

    # Открытое окно новых программ само не видит: берём свежие пути из системы, а то, что было только в окне, оставляем.
    function Update-SessionPath {
        $all = @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'), $env:Path) -join ';'
        $seen = @{}
        $keep = @()
        foreach ($p in ($all -split ';')) {
            if ($p.Trim() -eq '') { continue }
            $k = Norm $p
            if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $keep += $p.Trim() }
        }
        $env:Path = $keep -join ';'
    }

    # Папка в пути поиска и навсегда (у пользователя), и сразу в этом окне. $front — поставить первой.
    function Add-UserPath($dir, [bool]$front) {
        $k = Norm $dir
        $user = [Environment]::GetEnvironmentVariable('Path', 'User')
        $list = @()
        if ($user) { $list = @($user -split ';' | Where-Object { $_.Trim() -ne '' }) }
        $idx = -1
        for ($i = 0; $i -lt $list.Count; $i++) { if ((Norm ($list[$i])) -eq $k) { $idx = $i; break } }
        if (-not ($idx -ge 0 -and (-not $front -or $idx -eq 0))) {
            if ($idx -ge 0) { $list = @($list | Where-Object { (Norm $_) -ne $k }) }
            if ($front) { $list = @($dir) + $list } else { $list = $list + @($dir) }
            [Environment]::SetEnvironmentVariable('Path', ($list -join ';'), 'User')
        }
        $cur = @($env:Path -split ';' | Where-Object { $_.Trim() -ne '' })
        $has = @($cur | Where-Object { (Norm $_) -eq $k }).Count -gt 0
        if ($front) { $env:Path = (@($dir) + @($cur | Where-Object { (Norm $_) -ne $k })) -join ';' }
        elseif (-not $has) { $env:Path = ($cur + @($dir)) -join ';' }
    }

    # Настройка навсегда и сразу в этом окне: открытый терминал новых настроек сам не видит.
    function Set-UserVar($name, $value) {
        [Environment]::SetEnvironmentVariable($name, $value, 'User')
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }

    # --- поиск программ: проверяем запуском, а не наличием файла --------------------------
    function Find-Git {
        foreach ($c in @(Get-Command git -All -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' })) {
            $global:LASTEXITCODE = 1
            $null = & $c.Source --version 2>&1
            if ($LASTEXITCODE -eq 0) { return $c.Source }
        }
        foreach ($d in @("$env:ProgramFiles\Git\cmd", "${env:ProgramFiles(x86)}\Git\cmd", "$env:LOCALAPPDATA\Programs\Git\cmd")) {
            $g = Join-Path $d 'git.exe'
            if (Test-Path $g) {
                $global:LASTEXITCODE = 1
                $null = & $g --version 2>&1
                if ($LASTEXITCODE -eq 0) { Add-UserPath $d $false; return $g }
            }
        }
        return $null
    }

    # Git Bash лежит рядом с git: ищем bash.exe вверх по папкам. Системный bash.exe из WindowsApps (WSL) — не он.
    function Find-GitBash($git) {
        $d = Split-Path $git
        for ($i = 0; $i -lt 4 -and $d; $i++) {
            $b = Join-Path $d 'bin\bash.exe'
            if (Test-Path $b) { return $b }
            $d = Split-Path $d
        }
        foreach ($root in @("$env:ProgramFiles\Git", "${env:ProgramFiles(x86)}\Git", "$env:LOCALAPPDATA\Programs\Git")) {
            $b = Join-Path $root 'bin\bash.exe'
            if (Test-Path $b) { return $b }
        }
        return $null
    }

    # Заглушка python из магазина Microsoft тоже называется python и в пути поиска стоит раньше настоящего Python.
    function Test-PythonExe($exe, $prefix) {
        $global:LASTEXITCODE = 1
        $out = & $exe @prefix -c "import sys; print('ok' if sys.version_info >= (3, 9) else 'old')" 2>&1 | Out-String
        return ($LASTEXITCODE -eq 0 -and $out.Trim() -eq 'ok')
    }

    function Find-Python {
        foreach ($c in @(Get-Command python -All -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' })) {
            if (Test-PythonExe $c.Source @()) { return $c.Source }
        }
        $py = Get-Command py -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
        if ($py -and (Test-PythonExe $py.Source @('-3'))) {
            $global:LASTEXITCODE = 1
            $p = (& $py.Source -3 -c 'import sys; print(sys.executable)' 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and (Test-Path $p)) { return $p }
        }
        foreach ($mask in @("$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe")) {
            $found = @(Get-ChildItem $mask -ErrorAction SilentlyContinue | Sort-Object { [int](($_.Directory.Name -replace '\D', '0')) } -Descending)
            foreach ($f in $found) { if (Test-PythonExe $f.FullName @()) { return $f.FullName } }
        }
        return $null
    }

    function Find-Claude {
        $cands = @(Get-Command claude -All -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | ForEach-Object { $_.Source })
        $cands += (Join-Path $S.Bin 'claude.exe')
        foreach ($c in $cands) {
            if (-not (Test-Path $c)) { continue }
            $global:LASTEXITCODE = 1
            $null = & $c --version 2>&1
            if ($LASTEXITCODE -eq 0) { return $c }
        }
        return $null
    }

    # --- установка ------------------------------------------------------------------------
    # Без winget (на части Windows 10 его нет) или когда он не справился, ставим с сайта программы сами: для этого
    # пользователя, без окна «Разрешить изменения». Версии и контрольные суммы закреплены: подменённый файл не поставится.
    $S.Pryamo = @{
        'Git.Git'            = @{
            x64   = @('https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.4/Git-2.56.0.4-64-bit.exe', '4961a4a8cc778d8b6e00a5819e5fe4d078b754555aff7aedc2d77a5d74c2de80')
            arm64 = @('https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.4/Git-2.56.0.4-arm64.exe', 'e7dcc4adbb0eb373064598cd18bc75e60128707d816ead51cd9bd98e356f0075')
            Args  = @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/SUPPRESSMSGBOXES', ('/DIR="' + (Join-Path $env:LOCALAPPDATA 'Programs\Git') + '"'))
        }
        'Python.Python.3.13' = @{
            x64   = @('https://www.python.org/ftp/python/3.13.17/python-3.13.17-amd64.exe', '5da012101ba2e17113a9a1cd901e9ce1441086f2b7ecb5de06ec94163899a190')
            arm64 = @('https://www.python.org/ftp/python/3.13.17/python-3.13.17-arm64.exe', '3089a1977c32b26f5078e5a7d0285b7a861b8c96250c5dac3b6af59fbe9e9a75')
            Args  = @('/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=0', 'Include_test=0', 'Shortcuts=0')
        }
    }

    function Install-Direct($id) {
        $p = $S.Pryamo[$id]
        $arch = 'x64'
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { $arch = 'arm64' }
        $url = $p[$arch][0]
        $name = Split-Path $url -Leaf
        $f = Join-Path ([IO.Path]::GetTempPath()) $name
        Say "⏳ Скачиваю $name с сайта программы..."
        try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $f -ErrorAction Stop }
        catch { Say "⚠️ $name не скачался: $($_.Exception.Message)"; return }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash -ne $p[$arch][1]) {
            Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue
            Say "⚠️ $name не совпал с контрольной суммой — не ставлю."
            return
        }
        $proc = Start-Process -FilePath $f -ArgumentList $p.Args -Wait -PassThru
        Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue
        if ($proc.ExitCode -ne 0) { Say "⚠️ Установщик $name закончил с кодом $($proc.ExitCode)." }
        Update-SessionPath
    }

    # Ставим, пока $found не найдёт программу: winget для этого пользователя → с сайта → winget для всех (тут Windows
    # может спросить разрешение — это последний способ).
    function Install-Program($id, [scriptblock]$found) {
        $winget = (-not $env:METHOD_BEZ_WINGET) -and [bool](Get-Command winget -ErrorAction SilentlyContinue)
        if ($winget) {
            winget install -e --id $id --source winget --scope user --silent --disable-interactivity --accept-package-agreements --accept-source-agreements | Out-Host
            Update-SessionPath
            if (& $found) { return }
        }
        Install-Direct $id
        if (& $found) { return }
        if ($winget) {
            Say '⚠️ Два способа не сработали, пробую третий. Если Windows спросит «Разрешить изменения?» — человеку нажать «Да».'
            winget install -e --id $id --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements | Out-Host
            Update-SessionPath
        }
    }

    # Запуск Claude: возвращает код и весь текст ответа (в нём нет ключей: только список и сообщения установки).
    function Invoke-Claude([string[]]$argList) {
        $global:LASTEXITCODE = 1
        $text = & $S.Claude @argList 2>&1 | ForEach-Object { "$_" } | Out-String
        return @{ Code = $LASTEXITCODE; Text = $text }
    }

    # Настройки Claude: дописываем свои, чужие не трогаем. Файл читает и пишет Python: он точно сохранит всё остальное.
    # Значения в вывод не попадают, только имена.
    $S.PyMerge = @'
import json, os, shutil, sys
path = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8-sig") as f:
        raw = f.read()
    if raw.strip():
        data = json.loads(raw)
if not isinstance(data, dict):
    print("settings.json is not an object")
    sys.exit(2)
env = data.get("env")
if not isinstance(env, dict):
    env = {}
want = {"CLAUDE_CODE_USE_POWERSHELL_TOOL": "0", "PYTHONUTF8": "1"}
bash = os.environ.get("METHOD_BASH", "")
cur = env.get("CLAUDE_CODE_GIT_BASH_PATH")
if bash and not (isinstance(cur, str) and os.path.isfile(cur)):
    want["CLAUDE_CODE_GIT_BASH_PATH"] = bash
changed = [k for k, v in want.items() if env.get(k) != v]
if changed:
    if os.path.exists(path) and not os.path.exists(path + ".bak-metod"):
        shutil.copy2(path, path + ".bak-metod")
    env.update(want)
    data["env"] = env
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
print("changed: " + ", ".join(changed) if changed else "unchanged")
'@

    try {
        Say 'Установка метода KOROBEINIKOV AI (Windows)'
        Say ''

        # Система
        $os = $null
        try { $os = Get-CimInstance Win32_OperatingSystem } catch { Say '⚠️ Не смог проверить версию Windows, продолжаю.' }
        if ($os) {
            $ver = [Version]$os.Version
            if ($ver.Major -lt 10 -or ($ver.Major -eq 10 -and $ver.Build -lt 17763)) {
                Stop-Install "Claude работает на Windows 10 (версия 1809) и новее, у вас $($os.Caption)." 'обновите Windows: Пуск → Параметры → Обновление и безопасность → Центр обновления Windows.'
            }
            Say "✅ Система подходит: $($os.Caption)"
        }
        if (-not [Environment]::Is64BitOperatingSystem) {
            Stop-Install 'Нужна 64-разрядная Windows, у вас 32-разрядная.' 'метод на таком компьютере не заработает.'
        }
        Update-SessionPath
        Add-UserPath $S.Bin $false

        # Git: без него нет Git Bash, а охрана ключей работает только в нём
        $git = Find-Git
        if ($git) {
            Say '✅ Git уже стоит'
        } else {
            Say '⏳ Ставлю Git. Несколько минут экран может молчать, это нормально: идёт скачивание.'
            Install-Program 'Git.Git' { Find-Git }
            $git = Find-Git
            if (-not $git) { Stop-Install 'Git не поставился.' 'проверьте интернет и свободное место на диске. Если Windows просила разрешение, нужно было нажать «Да».' }
            Say '✅ Git поставлен'
        }
        $bash = Find-GitBash $git
        if (-not $bash) {
            # Git без Git Bash (урезанный, от другой программы): ставим полный Git для этого пользователя рядом
            Say '⏳ У этого Git нет Git Bash — ставлю полный Git.'
            Install-Program 'Git.Git' { Find-GitBash $git }
            $bash = Find-GitBash $git
        }
        if (-not $bash) { Stop-Install 'Не нашёл Git Bash (его ставит Git).' 'проверьте интернет и свободное место на диске.' }

        # Python: охрана ключей написана на нём
        $python = Find-Python
        if ($python) {
            Say '✅ Python уже стоит'
        } else {
            Say '⏳ Ставлю Python. Несколько минут экран может молчать, это нормально.'
            Install-Program 'Python.Python.3.13' { Find-Python }
            $python = Find-Python
            if (-not $python) { Stop-Install 'Python не поставился.' 'проверьте интернет и свободное место на диске.' }
            Say '✅ Python поставлен'
        }
        # Команда python должна вести к настоящему Python, а не к заглушке магазина Microsoft
        $first = Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
        if (-not $first -or (Norm (Split-Path $first.Source)) -ne (Norm (Split-Path $python))) { Add-UserPath (Split-Path $python) $true }

        # Claude: спрашиваем сам Claude, а не ищем файл — сломанная копия поставится заново.
        # Изнутри Claude берём ту копию, что нас запустила (у приложения она своя, команды claude может и не быть).
        $S.Claude = $null
        if ($S.Vnutri) {
            $global:LASTEXITCODE = 1
            $null = & $env:CLAUDE_CODE_EXECPATH --version 2>&1
            if ($LASTEXITCODE -eq 0) { $S.Claude = $env:CLAUDE_CODE_EXECPATH }
        }
        if ($S.Vnutri -and -not $S.Claude) {
            Stop-Install 'Claude, который запустил подготовку, не ответил.' 'полностью закройте Claude и откройте снова, потом попросите его поставить метод ещё раз.'
        }
        if (-not $S.Claude) { $S.Claude = Find-Claude }
        if ($S.Claude) {
            Say '✅ Claude уже стоит'
        } else {
            Say '⏳ Ставлю Claude. Несколько минут экран будет молчать, это нормально.'
            powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex' | Out-Host
            Update-SessionPath
            $S.Claude = Find-Claude
            if (-not $S.Claude) { Stop-Install 'Claude не поставился.' 'проверьте интернет и свободное место на диске.' }
            Say '✅ Claude поставлен'
        }
        Add-UserPath $S.Bin $false

        # Настройки охраны. Без них Claude уйдёт работать через PowerShell, а охрана видит только команды Git Bash.
        Set-UserVar 'CLAUDE_CODE_USE_POWERSHELL_TOOL' '0'
        Set-UserVar 'PYTHONUTF8' '1'
        $curBash = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User')
        if ($curBash -and (Test-Path $curBash)) { $bash = $curBash } else { Set-UserVar 'CLAUDE_CODE_GIT_BASH_PATH' $bash }
        # Настройки Git (в том числе концы строк) не трогаем: LF в файлах метода держит .gitattributes

        $tmp = Join-Path ([IO.Path]::GetTempPath()) 'metod-nastroyki.py'
        Set-Content -Path $tmp -Value $S.PyMerge -Encoding ASCII
        $env:METHOD_BASH = $bash
        $global:LASTEXITCODE = 1
        $merge = & $python -I $tmp 2>&1 | Out-String
        $mergeCode = $LASTEXITCODE
        Remove-Item Env:METHOD_BASH -ErrorAction SilentlyContinue
        Remove-Item $tmp -ErrorAction SilentlyContinue
        if ($mergeCode -eq 0) {
            Say '✅ Настройки охраны включены'
        } else {
            Say '⚠️ Файл настроек Claude (.claude\settings.json) не прочитался: настройки записаны только в Windows. Охране этого хватает, но лучше потом показать файл Claude.'
            Say "   $($merge.Trim())"
        }

        # Рабочая папка метода. Ответ «да» на вопрос Claude о папке действует и на проекты внутри неё, а в домашней не запоминается.
        New-Item -ItemType Directory -Force -Path $S.Work | Out-Null
        if (-not (Test-Path $S.Work)) { Stop-Install 'Не вышло создать папку vibecoding.' 'запустите установку ещё раз.' }

        # Пакет метода
        $list = Invoke-Claude @('plugin', 'list')
        if ($list.Text -match [regex]::Escape($S.Paket)) {
            Say '✅ Пакет метода уже стоит'
        } else {
            Say '⏳ Подключаю пакет метода...'
            $src = $S.Repo
            if ($S.Local) { $src = $S.Local }
            $r = Invoke-Claude @('plugin', 'marketplace', 'add', $src)
            if ($r.Code -ne 0 -and $r.Text -notmatch 'already') {
                Say $r.Text
                Stop-Install 'Не вышло подключить пакет метода.' 'проверьте интернет.'
            }
            $r = Invoke-Claude @('plugin', 'install', $S.Paket)
            if ($r.Code -ne 0 -and $r.Text -notmatch 'already') {
                Say $r.Text
                Stop-Install 'Не вышло поставить пакет метода.' 'проверьте интернет.'
            }
            $list = Invoke-Claude @('plugin', 'list')
            if ($list.Text -notmatch [regex]::Escape($S.Paket)) { Stop-Install 'Пакет метода не появился в списке Claude.' 'запустите установку ещё раз.' }
            Say '✅ Пакет метода поставлен'
        }
        # Строка над полем ввода приложения Claude (в терминале молчит). Не поставилась — работе не мешает.
        $stroka = 'stroka@' + $S.Polka
        if ($list.Text -match [regex]::Escape($stroka)) {
            Say '✅ Строка над полем ввода уже стоит'
        } else {
            $r = Invoke-Claude @('plugin', 'install', $stroka)
            if ($r.Code -eq 0 -or $r.Text -match 'already') { Say '✅ Строка над полем ввода поставлена' }
            else { Say '⚠️ Строка над полем ввода не поставилась: работе не мешает.' }
        }

        # Изнутри Claude: всё для знакомства и проекта в этом же чате (инструкция CLAUDE.md). Скрипты пакета — через Git Bash.
        $bad = $false
        if ($S.Vnutri) {
            $root = $null
            try {
                $j = Get-Content -LiteralPath (Join-Path $S.Home '.claude\plugins\installed_plugins.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $root = @($j.plugins.($S.Paket))[0].installPath
            } catch { Say "⚠️ Не прочитал список пакетов Claude: $($_.Exception.Message)" }
            if (-not $root -or -not (Test-Path (Join-Path $root 'skills\start\SKILL.md'))) {
                $root = Get-ChildItem (Join-Path $S.Home ".claude\plugins\cache\$($S.Polka)\osnova") -Directory -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
            }
            if (-not $root -or -not (Test-Path (Join-Path $root 'skills\start\SKILL.md'))) { Stop-Install 'Пакет стоит, но его папки нет на диске.' 'запустите подготовку ещё раз.' }
            $u = { param($p) $p -replace '\\', '/' }  # пути Windows с прямыми слешами понимают и Git Bash, и PowerShell
            $start = & $u (Join-Path $root 'skills\start')
            $py = & $u (Join-Path $root 'hooks\py.sh')
            $data = & $u (Join-Path $S.Home ".claude\plugins\data\osnova-$($S.Polka)")

            & $bash "$start/instrumenty.sh" 2>&1 | ForEach-Object { "$_" } | Out-Host
            if ($LASTEXITCODE -ne 0) { $bad = $true }
            & $bash $py "$start/nastroyki.py" obnovleniya 2>&1 | ForEach-Object { "$_" } | Out-Host
            if ($LASTEXITCODE -ne 0) { $bad = $true }

            # Личный доступ: одноразовая ссылка из бота. Ключ сервер отдаёт только самому запуску и сразу в закрытый файл.
            if ($env:METHOD_DOSTUP) {
                $d = $env:METHOD_DOSTUP.Trim()
                Remove-Item Env:METHOD_DOSTUP -ErrorAction SilentlyContinue  # ссылка одноразовая: повтор подготовки её не тратит
                if ($d -match '^https://korobeinikov-ai\.up\.railway\.app/u/[A-Za-z0-9_-]+$') {
                    $global:LASTEXITCODE = 1
                    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ("irm '" + $d + "?os=windows' | iex") 2>&1 | ForEach-Object { "$_" } | Out-Host
                    if ($LASTEXITCODE -ne 0) { Say 'ДОСТУП: ❌ не подключился (причина строкой выше), остальное поставлено' }
                } else {
                    Say 'ДОСТУП: ❌ это не ссылка из бота метода — попроси человека прислать текст из бота ещё раз'
                }
            }

            Say ''
            Say 'Проверка:'
            & $bash "$start/proverka.sh" 2>&1 | ForEach-Object { "$_" } | Out-Host
            if ($LASTEXITCODE -ne 0) { $bad = $true }
            Say ''
            Say ('BASH=' + (& $u $bash))
            Say "PY=$py"
            Say "ПРОВОДНИК=$start"
            Say "ДАННЫЕ=$data"
            if (Test-Path (Join-Path $data 'gotovo')) { Say 'ПРОВОДНИК_ПРОЙДЕН=да' } else { Say 'ПРОВОДНИК_ПРОЙДЕН=нет' }
            Say 'НАСТРОЙКИ:'
            & $bash $py "$start/nastroyki.py" pokazat 2>&1 | ForEach-Object { "$_" } | Out-Host
        }

        Say ''
        if ($S.Vnutri -and $bad) {
            Say 'ИТОГ: ❌ есть строки с ❌ выше — почини по подсказке и запусти подготовку ещё раз.'
        } elseif ($S.Vnutri) {
            Say 'ИТОГ: ✅ Подготовка закончена. Метод заработает в новом сеансе Claude.'
        } elseif ($S.NoRun) {
            Say '✅ Подготовка закончена. Claude не запускаю: это проверочный запуск.'
        } else {
            Set-Location $S.Work
            Say '✅ Подготовка закончена. Запускаю Claude.'
            Say 'На первых вопросах нажимайте Enter, потом откроется браузер: войдите своей подпиской.'
            Say '⚠️ На вопросе про папку (Yes, I trust this folder) сначала нажмите стрелку вниз, потом Enter: там по умолчанию стоит «нет».'
            Say '⚠️ Когда Claude скажет, что всё готово, закройте это окно и откройте новое: иначе новые окна не найдут Claude.'
            Say 'Дальше Claude проведёт сам.'
            & $S.Claude $S.Fraza

            # Проводник отмечает себя в постоянной папке пакета. Нет отметки: Claude закрылся раньше времени, чаще всего на вопросе про папку выбрано «нет».
            $done = Join-Path $S.Home ".claude\plugins\data\osnova-$($S.Polka)\gotovo"
            Say ''
            if (Test-Path $done) {
                Say '✅ Проводник пройден. Остался один перезапуск: закройте это окно и откройте новое.'
            } else {
                Say '⚠️ Claude закрылся раньше, чем закончил знакомство. Ничего не потеряно: вставьте в терминал строку ниже. На вопросе про папку выберите Yes, I trust this folder: сначала стрелка вниз, потом Enter.'
                Say '  cd ~\vibecoding; claude Начнём'
            }
        }
        $global:LASTEXITCODE = [int]$bad
    } catch {
        if ($_.Exception.Message -ne 'METHOD_STOP') {
            Write-Host ''
            Write-Host "❌ Что-то пошло не так: $($_.Exception.Message) (строка $($_.InvocationInfo.ScriptLineNumber))" -ForegroundColor Red
            Say-Again
        }
        $global:LASTEXITCODE = 1
    }
}
