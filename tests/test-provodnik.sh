#!/usr/bin/env bash
# Тесты проводника /start под Windows (Git Bash): программы, проверка компьютера, настройки «как у автора»,
# строка внизу окна, заведение проекта. Всё идёт во временной «домашней» папке с русским именем и пробелом:
# настоящие настройки, папки и git человека (или раннера) не трогаются.
# Запуск: bash tests/test-provodnik.sh (на Windows — настоящие программы с GitHub; на Mac — только то, что от системы не зависит).
set -uo pipefail
REPO="$(cd "$(dirname "${0//\\//}")/.." && pwd)"
S="$REPO/plugins/osnova/skills/start"
H="$REPO/plugins/osnova/hooks"
case "$OSTYPE" in msys* | cygwin*) WIN=1 ;; *) WIN=0 ;; esac
fail=0
ok()  { echo "✅ $1"; }
bad() { echo "❌ $1"; fail=1; }
skip() { echo "⏭️  пропущено: $1"; }

ROOT_T=$(mktemp -d)
FAKE="$ROOT_T/Иван Петров"; mkdir -p "$FAKE"
export HOME="$FAKE"; unset CLAUDE_CONFIG_DIR
[ $WIN = 1 ] && export USERPROFILE="$(cygpath -w "$FAKE")"
C="$FAKE/.claude/settings.json"; D="$FAKE/data"
BIN="$FAKE/.local/bin"
# Тесты ставят папку программ в путь Windows и сами её оттуда убирают
KBPS="$ROOT_T/userpath.ps1"
cat > "$KBPS" <<'EOF'
param([string]$Action)
$d = $env:KB_BIN.TrimEnd('\')
$items = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ })
if ($Action -eq 'has') {
  if ($items | Where-Object { $_.TrimEnd('\') -ieq $d }) { 'yes' } else { 'no' }
} else {
  [Environment]::SetEnvironmentVariable('Path', (($items | Where-Object { $_.TrimEnd('\') -ine $d }) -join ';'), 'User')
}
EOF
userpath() { KB_BIN="$(cygpath -w "$BIN")" powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(cygpath -w "$KBPS")" "$1" | tr -d '\r'; }
finish() {
  [ $WIN = 1 ] && userpath remove >/dev/null 2>&1
  rm -rf "$ROOT_T"
}
trap finish EXIT

# Python: на Windows — так, как его запускает пакет (мимо заглушки магазина Microsoft), на Mac — python3
PY() { if [ $WIN = 1 ]; then bash "$H/py.sh" "$@"; else python3 "$@"; fi; }
N() { PY "$S/nastroyki.py" "$@"; }
# Файлы с CR внутри (концы строк CRLF) из папок/файлов. Делаем Python-ом: grep на Windows «съедает» CR и ничего не находит
CRF() { PY -c '
import pathlib, sys
for a in sys.argv[1:]:
    p = pathlib.Path(a)
    for f in [p] if p.is_file() else [x for x in p.rglob("*") if x.is_file() and ".git" not in x.relative_to(p).parts]:
        b = f.read_bytes()
        if b"\0" not in b and b"\r" in b: print(f)' "$@"; }
# eval — только для условий, написанных здесь же в тесте
J() { PY -c 'import json,sys; s=json.load(open(sys.argv[1],encoding="utf-8-sig")); sys.exit(0 if eval(sys.argv[2]) else 1)' "$C" "$1"; }

# --- на месте ли всё нужное и нет ли следов Mac
[ -f "$S/SKILL.md" ] && [ -f "$S/instrumenty.sh" ] && [ -f "$S/proverka.sh" ] && [ -f "$S/stroka.py" ] && [ -f "$H/py.sh" ] \
  && ok "состав: файлы проводника и запуск Python на месте" || bad "состав: нет файла проводника или hooks/py.sh"
if grep -rnE 'osascript|pbpaste|pbcopy|xcode-select|open -a |apple-darwin|Homebrew|\.zshrc|macOS|korobeinikov-ai-method|/Users/' "$S" >/dev/null; then
  bad "следы Mac в проводнике: $(grep -rnoE 'osascript|pbpaste|pbcopy|xcode-select|open -a |apple-darwin|Homebrew|\.zshrc|macOS|korobeinikov-ai-method|/Users/' "$S" | head -3 | tr '\n' ' ')"
else ok "следы Mac: в проводнике нет"; fi
grep -qE 'python3 "' "$S/SKILL.md" && bad "SKILL.md: голый python3 в команде" || ok "SKILL.md: Python запускается через py.sh"
crlf=$(CRF "$S"); [ -z "$crlf" ] && ok "концы строк: файлы проводника с LF" || bad "концы строк: CRLF в $(echo "$crlf" | head -3 | tr '\n' ' ')"
for f in "$S"/*.py; do PY -c 'import sys; compile(open(sys.argv[1],encoding="utf-8").read(), sys.argv[1], "exec")' "$f" \
  || bad "синтаксис: $(basename "$f")"; done
for f in "$S"/*.sh; do bash -n "$f" || bad "синтаксис: $(basename "$f")"; done

# --- программы: что уже есть — не качается; не скачалось — видно; подмена не ставится
B="$FAKE/fakebin"; mkdir -p "$B"
for p in gh gitleaks ruff; do printf '#!/bin/sh\n' > "$B/$p"; chmod +x "$B/$p"; done
printf '#!/bin/sh\ntouch "%s/SKACHAL"\nexit 1\n' "$FAKE" > "$B/curl"; chmod +x "$B/curl"
PATH="$B:/usr/bin:/bin" bash "$S/instrumenty.sh" >/dev/null && [ ! -e "$FAKE/SKACHAL" ] \
  && ok "программы: что есть — не качается" || bad "программы: качает уже поставленное"
rm "$B/ruff"; out=$(PATH="$B:/usr/bin:/bin" bash "$S/instrumenty.sh" 2>/dev/null); code=$?
[ $code -ne 0 ] && echo "$out" | grep -q "❌ ruff" && ok "программы: сбой скачивания виден" || bad "программы: сбой скачивания молчит"
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && echo junk > "$2"; shift; done\n' > "$B/curl"
out=$(PATH="$B:/usr/bin:/bin" bash "$S/instrumenty.sh" 2>/dev/null); code=$?
[ $code -ne 0 ] && echo "$out" | grep -q "контрольной суммой" && [ ! -e "$BIN/ruff.exe" ] \
  && ok "программы: подменённый файл не ставится" || bad "программы: подменённый файл поставился"
rm -rf "$B" "$FAKE/SKACHAL" "$FAKE/.local"

# --- программы: настоящие сборки Windows с GitHub (сумма сверяется, файл запускается) и путь Windows
if [ $WIN = 1 ]; then
  echo "    unzip: $(command -v unzip || echo нет); sha256sum: $(command -v sha256sum || echo нет); curl: $(command -v curl || echo нет)"
  # путь без папок, где эти программы уже стоят у раннера: качается и проверяется настоящее
  CLEAN=""; IFS=: read -ra DIRS <<< "$PATH"
  for d in "${DIRS[@]}"; do
    [ -e "$d/gh.exe" ] || [ -e "$d/gitleaks.exe" ] || [ -e "$d/ruff.exe" ] || [ -e "$d/railway.exe" ] || CLEAN="$CLEAN:$d"
  done
  CLEAN="${CLEAN#:}"
  [ "$(userpath has)" = no ] || bad "путь Windows: папка была там до теста"
  out=$(PATH="$CLEAN" bash "$S/instrumenty.sh" 2>&1); code=$?; echo "$out" | sed 's/^/    /'
  [ $code -eq 0 ] && ok "программы: gh, gitleaks, ruff поставлены" || bad "программы: сбой установки (код $code)"
  for p in gh gitleaks ruff; do
    "$BIN/$p.exe" --version >/dev/null 2>&1 && ok "программы: $p.exe запускается" || bad "программы: $p.exe не запускается"
  done
  [ "$(userpath has)" = yes ] && echo "$out" | grep -q "добавлена в путь" \
    && ok "путь Windows: папка программ дописана в путь пользователя" || bad "путь Windows: папка программ не дописана"
  PATH="$CLEAN" bash "$S/instrumenty.sh" railway; code=$?
  [ $code -eq 0 ] && "$BIN/railway.exe" --version >/dev/null 2>&1 && ok "программы: railway.exe поставлен и запускается" || bad "программы: railway не встал (код $code)"
  out=$(PATH="$BIN:$CLEAN" bash "$S/instrumenty.sh" 2>&1); code=$?
  [ $code -eq 0 ] && echo "$out" | grep -q "gh уже есть" && ! echo "$out" | grep -q "добавлена в путь" \
    && ok "программы: повторный запуск ничего не качает и путь не дописывает второй раз" || bad "программы: повторный запуск что-то меняет (код $code)"
  # распаковка без unzip (так будет у человека со старым Git): запасной способ — tar.exe из Windows
  rm -f "$BIN/ruff.exe"
  out=$(KOROBEINIKOV_NO_UNZIP=1 PATH="$BIN:$CLEAN" bash "$S/instrumenty.sh" 2>&1); code=$?
  [ $code -eq 0 ] && echo "$out" | grep -q "через tar.exe" && "$BIN/ruff.exe" --version >/dev/null 2>&1 \
    && ok "программы: без unzip ruff распаковывается запасным способом (tar.exe)" || { bad "программы: запасная распаковка не сработала (код $code)"; echo "$out" | sed 's/^/    /'; }
  export PATH="$BIN:$PATH"
else
  skip "настоящие сборки Windows (на Mac не запускаются)"
fi

# --- проверка компьютера (заглушки gh и gitleaks: настоящие не нужны; Claude уже работает — его не проверяем)
PB="$FAKE/pbin"; mkdir -p "$PB"
for p in claude gh gitleaks; do printf '#!/bin/sh\nexit 0\n' > "$PB/$p"; chmod +x "$PB/$p"; done
GITBASH="$PB/claude"  # любой существующий файл: проверяется только то, что он есть
pv() { env PATH="$PB:$PATH" CLAUDE_CODE_USE_POWERSHELL_TOOL=0 PYTHONUTF8=1 CLAUDE_CODE_GIT_BASH_PATH="$GITBASH" "$@" bash "$S/proverka.sh" 2>&1; }
out=$(pv); code=$?
[ $code -eq 0 ] && echo "$out" | grep -q "✅ Охрана секретов срабатывает" && echo "$out" | grep -q "✅ Python" \
  && echo "$out" | grep -q "✅ Команды идут через охрану" && ! echo "$out" | grep -q "Zed" \
  && ok "проверка: на здоровом компьютере всё ✅, охрана срабатывает" || { bad "проверка: здоровый компьютер не прошёл (код $code)"; echo "$out" | sed 's/^/    /'; }
echo "$out" | grep -qiE "apple|xcode|homebrew" && bad "проверка: говорит про Apple" || ok "проверка: без советов про Apple"
out=$(pv CLAUDE_CODE_USE_POWERSHELL_TOOL=1); code=$?
[ $code -ne 0 ] && echo "$out" | grep -q "мимо охраны" && ok "проверка: включённый PowerShell замечен" || bad "проверка: PowerShell не замечен (код $code)"
out=$(pv CLAUDE_CODE_GIT_BASH_PATH="$FAKE/net-takogo-faila"); code=$?
[ $code -ne 0 ] && echo "$out" | grep -q "ищет Git Bash не там" && ok "проверка: неверный путь к Git Bash замечен" || bad "проверка: неверный путь к Git Bash не замечен (код $code)"
out=$(pv PYTHONUTF8=); code=$?
[ $code -eq 0 ] && echo "$out" | grep -q "⚠️ Русские буквы" && ok "проверка: без UTF-8 — предупреждение, не поломка" || bad "проверка: UTF-8 не замечен (код $code)"
out=$(pv CLAUDE_CODE_USE_POWERSHELL_TOOL=1)
echo "$out" | grep -q "METHOD_NO_LAUNCH=1; irm https://raw.githubusercontent.com/korobeinikov-ai/method-windows/main/install.ps1" \
  && ok "проверка: подсказка — строка подготовки целиком, переменные не съедены" || bad "проверка: в подсказке нет строки подготовки"
if [ $WIN = 1 ]; then
  # так Claude Code подставляет пути в команды из SKILL.md: с обратными слешами (и вперемешку с прямыми)
  WS="$(cygpath -w "$S")"
  for script in "$WS\\proverka.sh" "$WS/proverka.sh"; do
    out=$(env PATH="$PB:$PATH" CLAUDE_CODE_USE_POWERSHELL_TOOL=0 PYTHONUTF8=1 bash "$script" 2>&1); code=$?
    echo "$out" | grep -q "✅ Охрана секретов срабатывает" && ok "проверка: запуск по пути Windows ($script)" \
      || { bad "проверка: путь Windows не понят ($script, код $code)"; echo "$out" | head -5 | sed 's/^/    /'; }
  done
  out=$(bash "$WS/../../hooks/py.sh" "$WS/nastroyki.py" pokazat 2>&1)
  echo "$out" | grep -qE "Поменяется|Всё уже стоит" && ok "настройки: py.sh и скрипт по путям Windows запускаются" || bad "настройки: путь Windows не понят ($out)"
fi
rm -rf "$PB"

# --- автообновление: всем, без вопроса, только оно
N obnovleniya >/dev/null
J "s['extraKnownMarketplaces']['korobeinikov-ai-windows']['autoUpdate'] is True and s['extraKnownMarketplaces']['korobeinikov-ai-windows']['source']['repo']=='korobeinikov-ai/method-windows' and 'model' not in s and 'permissions' not in s" \
  && ok "обновления: полка Windows включена отдельно от остальных настроек" || bad "обновления: не включились или притащили лишнее"
N obnovleniya | grep -q "уже включено" && ok "обновления: повторно — «уже включено»" || bad "обновления: повтор что-то меняет"
grep -q 'korobeinikov-ai/method"' "$S/nastroyki.json" && bad "обновления: в настройках адрес полки Mac" || ok "обновления: адрес полки Mac нигде не остался"
rm -f "$C" "$FAKE/.claude"/settings.backup-*.json

# --- настройки
VER=$(sed -n 's/.*"versiya": *\([0-9][0-9]*\).*/\1/p' "$S/nastroyki.json" | head -1 | tr -d '\r')
N ustanovit --data "$D" >/dev/null
J "s['model']=='opus' and 'Read(**/.env)' in s['permissions']['deny'] and s['extraKnownMarketplaces']['korobeinikov-ai-windows']['autoUpdate'] is True" \
  && [ "$(cat "$D/nastroyki-versiya")" = "$VER" ] && ok "настройки: с нуля ставятся, версия запомнена" || bad "настройки: с нуля не встали"
[ -z "$(CRF "$C")" ] && ok "настройки: файл с LF" || bad "настройки: в файле CRLF"
J "'Bash(*Clipboard*)' in s['permissions']['deny'] and not any('pbpaste' in r for r in s['permissions']['deny'])" \
  && ok "настройки: буфер обмена Windows закрыт, следов pbpaste нет" || bad "настройки: буфер обмена не закрыт"
# запасной рубеж: запреты и «спросить» есть и для PowerShell, и для чтения .env средствами Windows
J "all(('PowerShell' + r[4:]) in s['permissions']['deny'] for r in s['permissions']['deny'] if r.startswith('Bash(') and ('railway' in r or 'Clipboard' in r)) and all(r in s['permissions']['deny'] for r in ('Bash(type *.env*)', 'Bash(findstr*.env*)', 'Bash(*Get-Content*.env*)', 'Bash(*Select-String*.env*)', 'PowerShell(*Get-Content*.env*)', 'PowerShell(*Remove-Item*-Recurse*)')) and all(r in s['autoMode']['soft_deny'] for r in ('PowerShell(*--no-verify*)', 'PowerShell(*VERIFY_OK*)', 'PowerShell(*core.hooksPath*)', 'PowerShell(*railway up*)', 'PowerShell(*git push*--force*)', 'PowerShell(*klyuch.py*peredat*)'))" \
  && ok "настройки: запреты и «спросить» продублированы для PowerShell, чтение .env через type/Get-Content закрыто" || bad "настройки: запасной рубеж для PowerShell неполный"
N pokazat | grep -q "Всё уже стоит" && ok "настройки: повторно — «всё уже стоит»" || bad "настройки: повторно что-то меняет"
echo '{"model":"sonnet","permissions":{"allow":["Bash(npm:*)"]},"theme":"light"}' > "$C"
N pokazat | grep -q "было: sonnet → станет: opus" && ok "настройки: показ «было → станет»" || bad "настройки: показ без «было → станет»"
N ustanovit --data "$D" >/dev/null
J "s['theme']=='light' and 'Bash(npm:*)' in s['permissions']['allow'] and 'Bash(ls:*)' in s['permissions']['allow'] and s['model']=='opus'" \
  && ok "настройки: свои настройки человека сохранены" || bad "настройки: затёрли настройки человека"
ls "$FAKE/.claude"/settings.backup-*.json >/dev/null 2>&1 && ok "настройки: копия старых сделана" || bad "настройки: нет копии старых"
# то, что записала установка Windows (блок env), и невидимая метка BOM от PowerShell
printf '\xef\xbb\xbf{"env":{"CLAUDE_CODE_GIT_BASH_PATH":"C:/Git/bin/bash.exe","PYTHONUTF8":"1","CLAUDE_CODE_USE_POWERSHELL_TOOL":"0"},"theme":"dark"}' > "$C"
N obnovleniya >/dev/null; code=$?
J "s['env']['CLAUDE_CODE_GIT_BASH_PATH']=='C:/Git/bin/bash.exe' and s['env']['PYTHONUTF8']=='1' and s['env']['CLAUDE_CODE_USE_POWERSHELL_TOOL']=='0' and s['theme']=='dark' and 'korobeinikov-ai-windows' in s['extraKnownMarketplaces']" \
  && [ $code -eq 0 ] && [ "$(head -c1 "$C")" = "{" ] && ok "настройки: блок env от установки сохранён, файл с меткой BOM прочитан" || bad "настройки: затёрт env или не прочитан файл с BOM (код $code)"
N ustanovit --data "$D" >/dev/null
J "s['env']['CLAUDE_CODE_GIT_BASH_PATH']=='C:/Git/bin/bash.exe' and s['env']['CLAUDE_CODE_USE_POWERSHELL_TOOL']=='0' and s['model']=='opus'" \
  && ok "настройки: после полной установки env на месте" || bad "настройки: полная установка затёрла env"
if [ $WIN = 0 ]; then
  chmod 600 "$C"; echo '{"model":"sonnet"}' > "$C"; N ustanovit --data "$D" >/dev/null
  [ "$(stat -f %Lp "$C" 2>/dev/null || stat -c %a "$C")" = 600 ] && ok "настройки: закрытый файл остался закрытым" || bad "настройки: права файла потеряны"
fi
J "not any(r.startswith(('Bash(git diff', 'Bash(git log')) for r in s['permissions']['allow']) and 'Bash(gh auth status)' in s['permissions']['allow'] and 'Bash(*--no-verify*)' in s['autoMode']['soft_deny'] and 'Bash(*VERIFY_OK*)' in s['autoMode']['soft_deny']" \
  && ok "настройки: без лазеек мимо запретов, обход проверки секретов — только с вопросом" || bad "настройки: лазейка в разрешениях"
echo '{oops' > "$C"; N ustanovit --data "$D" >/dev/null; code=$?
[ $code -eq 1 ] && [ "$(cat "$C")" = '{oops' ] && ok "настройки: битый файл не трогается" || bad "настройки: битый файл перезаписан (код $code)"
echo '{"permissions":"кривое"}' > "$C"; N pokazat | grep -q "не по форме" && ok "настройки: кривое значение не затирается молча" || bad "настройки: кривое значение затёрто молча"
rm -f "$D/nastroyki-versiya"; N otkaz --data "$D" >/dev/null
[ "$(cat "$D/nastroyki-versiya" 2>/dev/null)" = "$VER" ] && ok "настройки: отказ запомнен" || bad "настройки: отказ не запомнен"
rm -f "$C"; N ustanovit --data "$D" >/dev/null

# --- строка внизу окна: сам Python-файл и команда из настроек (как её запустит Claude Code)
JS='{"model":{"display_name":"Opus 5.5"},"effort":{"level":"high"},"workspace":{"current_dir":"/x/кофейня"},"context_window":{"context_window_size":1000000,"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":23}}}'
st=$(printf '%s' "$JS" | PY "$S/stroka.py")
echo "$st" | grep -q "кофейня" && echo "$st" | grep -q "Opus 5.5" && echo "$st" | grep -q "разговор 12%" && echo "$st" | grep -q "5ч 23%" \
  && ok "строка: папка (по-русски), модель, разговор, лимит" || bad "строка: не всё показала"
echo 'oops' | PY "$S/stroka.py" 2>/dev/null | grep -q "📁" && ok "строка: кривые данные — папка остаётся" || bad "строка: на кривых данных пусто"
if [ $WIN = 1 ]; then
  st=$(printf '%s' '{"workspace":{"current_dir":"C:\\Users\\Ivan\\vibecoding\\kofeynya"}}' | PY "$S/stroka.py")
  echo "$st" | grep -q "kofeynya" && ! echo "$st" | grep -q 'vibecoding' && ok "строка: путь Windows с обратными слешами — берётся имя папки" || bad "строка: путь Windows не разобран"
fi
# команда из настроек: без PYTHONUTF8 в окружении русские буквы всё равно доходят
DATA="$FAKE/.claude/plugins/data/osnova-korobeinikov-ai-windows"; mkdir -p "$DATA"; cp "$S/stroka.py" "$DATA/stroka.py"  # так делает session-start.sh
cmd=$(PY -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8-sig"))["statusLine"]["command"])' "$C")
st=$(printf '%s' "$JS" | env -u PYTHONUTF8 -u PYTHONIOENCODING bash -c "$cmd" 2>&1)
echo "$st" | grep -q "кофейня" && echo "$st" | grep -q "Opus 5.5" && ok "строка: команда из настроек запускает настоящий Python, русские буквы целы" || bad "строка: команда из настроек не сработала"
FB="$FAKE/stub"; mkdir -p "$FB"
printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store"\n' > "$FB/python"; chmod +x "$FB/python"
st=$(printf '%s' "$JS" | PATH="$FB:$PATH" bash -c "$cmd" 2>&1)
echo "$st" | grep -q "кофейня" && ok "строка: заглушка python («Python was not found») пропущена" || bad "строка: заглушка python сломала строку"
if [ $WIN = 1 ] && command -v py >/dev/null; then
  cp /usr/bin/false.exe "$FB/python.exe"; cp /usr/bin/false.exe "$FB/python3.exe"; rm -f "$FB/python"
  st=$(printf '%s' "$JS" | PATH="$FB:$PATH" bash -c "$cmd" 2>&1)
  echo "$st" | grep -q "кофейня" && ok "строка: python и python3 не работают — нашёлся py" || bad "строка: py не нашёлся"
fi
rm -rf "$FB"

# --- заведение проекта. Пакет здесь «скачан как у человека с заменой концов строк»: файлы скелета с CRLF
CP="$FAKE/plugin-crlf"; mkdir -p "$CP"; cp -R "$REPO/plugins/osnova/." "$CP/"
PY -c '
import pathlib, sys
for p in pathlib.Path(sys.argv[1]).rglob("*"):
    if p.is_file() and b"\0" not in p.read_bytes():
        b = p.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"); p.write_bytes(b)' "$CP/skelet"
[ -n "$(CRF "$CP/skelet")" ] && ok "проект: пакет для проверки скачан с CRLF" || bad "проект: не удалось сделать скелет с CRLF"
P() { PY "$CP/skills/start/novyi_proekt.py" "$@"; }
R="$FAKE/vibecoding/kofeynya"
P kofeynya "Кофейня «Зерно»" "учёт продаж" --bez-github --data "$D" --zadacha "итоги продаж
по товарам" >/dev/null; code=$?
[ "$(cat "$D/zadacha" 2>/dev/null)" = "итоги продаж по товарам" ] && ok "проект: задача запомнена одной строкой для следующего сеанса" \
  || bad "проект: задача не запомнена"
[ $code -eq 0 ] && grep -q "Кофейня «Зерно»" "$R/CLAUDE.md" && grep -q "учёт продаж" "$R/STRUCTURE.md" \
  && grep -q "учёт продаж" "$R/IDEYA.md" && ! grep -q "{{" "$R/CLAUDE.md" "$R/STRUCTURE.md" "$R/IDEYA.md" \
  && ok "проект: скелет заведён в «домашней» папке с русским именем, метки заполнены" || bad "проект: скелет не заведён (код $code)"
crlf=$(CRF "$R" | head -3)
[ -z "$crlf" ] && ok "проект: все файлы скелета с LF (даже если пакет скачан с CRLF)" || bad "проект: CRLF в файлах: $crlf"
[ "$(git -C "$R" config core.hooksPath)" = ".githooks" ] && [ "$(git -C "$R" config core.autocrlf)" = false ] \
  && [ "$(git -C "$R" rev-list --count HEAD 2>/dev/null)" = 1 ] \
  && ok "проект: охрана подключена, первая версия сохранена" || bad "проект: нет охраны или первой версии"
[ -f "$D/gotovo" ] && [ "$(cat "$D/sprosit-zadachu")" != "" ] && ok "проект: проводник отмечен пройденным" || bad "проект: отметки проводника нет"
rm -rf "$R/.git"; P kofeynya "x" "y" --bez-github >/dev/null; code=$?
[ $code -eq 0 ] && [ "$(git -C "$R" rev-list --count HEAD 2>/dev/null)" = 1 ] && grep -q "Кофейня «Зерно»" "$R/CLAUDE.md" \
  && ok "проект: упал посередине — повтор продолжает с места" || bad "проект: повтор не продолжил (код $code)"
mkdir -p "$FAKE/vibecoding/chuzhaya"; touch "$FAKE/vibecoding/chuzhaya/x"
P chuzhaya "x" "y" --bez-github >/dev/null; [ $? -eq 1 ] && ok "проект: чужую папку не трогает" || bad "проект: полез в чужую папку"
P pusto " " "y" --bez-github >/dev/null; [ $? -eq 2 ] && ok "проект: пустое название отклонено" || bad "проект: пустое название принято"
[ -z "$(git config --global user.email)" ] && ok "проект: общие настройки git человека не тронуты" || bad "проект: тронул общие настройки git"
P "Bad Name" "x" "y" --bez-github >/dev/null; [ $? -eq 2 ] && ok "проект: кривое имя папки отклонено" || bad "проект: кривое имя принято"
P con "x" "y" --bez-github >/dev/null; [ $? -eq 2 ] && [ ! -e "$FAKE/vibecoding/con" ] && ok "проект: имя, запрещённое Windows (con), отклонено" || bad "проект: имя con принято"

# охрана проекта: сканер секретов перед каждым сохранением. Ключи собираются на лету: готовой строки нет ни в файле, ни в выводе
if command -v gitleaks >/dev/null; then
  rnd() { PY -c "import random,string; print(''.join(random.choice(string.ascii_letters+string.digits) for _ in range($1)))"; }
  tok="ghp_$(rnd 36)"
  echo "TOKEN = \"$tok\"" > "$R/config.py"; git -C "$R" add config.py
  git -C "$R" commit -qm leak >/dev/null 2>&1; code=$?
  [ $code -ne 0 ] && [ "$(git -C "$R" rev-list --count HEAD)" = 1 ] && ok "проект: секрет в коде не сохраняется (gitleaks)" || bad "проект: секрет сохранился"
  git -C "$R" reset -q --hard HEAD
  base=$(git -C "$R" rev-parse HEAD)
  sohranit() { echo "$1" > "$R/config.py"; git -C "$R" add config.py; git -C "$R" commit -qm proba >/dev/null 2>&1; code=$?
    git -C "$R" reset -q --hard "$base"; rm -f "$R/config.py"; return $code; }
  tg="7123456789:AA$(rnd 33)"
  pg="postgresql://postgres.abcdefgh:$(rnd 24)@aws-0-eu-central-1.pooler.supabase.com:6543/postgres"
  for s in "TOKEN = \"$tg\"" "bot = Bot(token=\"$tg\")" "DATABASE_URL = \"$pg\"" "client = create_client(url, \"sb_secret_$(rnd 32)\")"; do
    sohranit "$s" && bad "проект: сканер пропустил ${s%%=*}" || ok "проект: сканер поймал ${s%%=*}"
  done
  db="postgresql://"  # строка собирается здесь же
  for s in "url = \"${db}user:password@localhost:5432/app\"" "url = \"${db}postgres:[YOUR-PASSWORD]@db.abc.supabase.co:5432/postgres\"" \
      'TOKEN = "123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"'; do
    # само значение (даже заглушку вида «адрес с паролем») в журнал не печатаем: только имя
    sohranit "$s" && ok "проект: заглушка без тревоги: ${s%%=*}" || bad "проект: ложная тревога: ${s%%=*}"
  done
  if [ -d "$REPO/plugins/osnova/skills/telegram-bot/shablon" ]; then
    cp -R "$REPO/plugins/osnova/skills/telegram-bot/shablon" "$R/bot"; git -C "$R" add bot
    git -C "$R" commit -qm bot >/dev/null 2>&1 && ok "проект: шаблон бота сохраняется без тревоги" || bad "проект: сканер споткнулся о шаблон бота"
    git -C "$R" reset -q --hard "$base"
  fi
else
  skip "gitleaks не установлен"
fi

exit $fail
