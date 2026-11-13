#!/usr/bin/env bash
# Тесты охраны: хуки пакета, запуск Python, сторож ключей в скелете проекта.
# Хуку подаём JSON так же, как Claude Code, и смотрим ответ. Печатает ✅/❌ по шагам, при провале выходит с кодом 1.
# Запуск: Git Bash на Windows (главная мерка) или Mac (быстрая проверка у автора): bash tests/test-hooks.sh
# KOROBEINIKOV_TEST_STRICT=1 — нет gitleaks, ruff или node: это провал, а не пропуск (так запускает общий прогон).
# Значения ключей нигде не печатаются; ключи-подделки собираются из кусков во время запуска.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OSN="$REPO/plugins/osnova"
H="$OSN/hooks"
STRICT="${KOROBEINIKOV_TEST_STRICT:-0}"
fail=0
ok()   { echo "✅ $1"; }
bad()  { echo "❌ $1"; fail=1; }
skip() { if [ "$STRICT" = 1 ]; then bad "$1 (нет нужной программы, а прогон строгий)"; else echo "⏭  пропуск: $1"; fi; }
# check <код> <описание> <команда...> — команда должна завершиться с этим кодом
check() { local want=$1 what=$2; shift 2; "$@" >/dev/null 2>&1; local got=$?; [ "$got" -eq "$want" ] && ok "$what" || bad "$what (код $got, ждали $want)"; }

ROOTTMP=$(mktemp -d)
mk() { mixed "$(mktemp -d "$ROOTTMP/d.XXXXXX")"; }  # путь в виде C:/..., как его шлёт Claude Code (в /tmp/... Python Windows не заходит)
SID="test-hooks-$$"
LOGDIR=""
cleanup() { rm -rf "$ROOTTMP"; [ -n "$LOGDIR" ] && rm -f "$(cygpath -u "$LOGDIR" 2>/dev/null || printf '%s' "$LOGDIR")/claude-verify-$SID.log"; }
trap cleanup EXIT

# Пути в трёх видах, в каких они приходят хуку на Windows: C:/work/x, C:\work\x, /c/work/x.
# На Mac все три — обычный путь.
if command -v cygpath >/dev/null 2>&1; then
  WIN=1
  mixed()  { cygpath -m "$1"; }
  native() { cygpath -w "$1"; }
  posix()  { local m; m=$(cygpath -m "$1"); printf '/%s%s' "$(printf '%s' "${m:0:1}" | tr 'A-Z' 'a-z')" "${m:2}"; }
else
  WIN=0
  mixed()  { printf '%s' "$1"; }
  native() { printf '%s' "$1"; }
  posix()  { printf '%s' "$1"; }
fi
HM="$(mixed "$H")"
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }             # строка -> внутрь JSON
crlf() { tr -d '\r'; }                                                  # Python на Windows печатает \r\n
PYX() { bash "$H/py.sh" "$@"; }                                         # Python так, как зовёт его hooks.json
# J <команда> <папка> [событие] [имя инструмента] -> JSON хука
J() { printf '{"hook_event_name":"%s","tool_name":"%s","tool_input":{"command":"%s"},"cwd":"%s"}' \
        "${3:-PreToolUse}" "${4:-Bash}" "$(jesc "$1")" "$(jesc "$2")"; }
# run <хук.py> <json> [папка запуска]
run() { printf '%s' "$2" | (cd "${3:-.}" && bash "$H/py.sh" "$HM/$1"); }
G() { git -C "$1" -c user.name=t -c user.email=t@example.com "${@:2}"; }
mkrepo() { local d; d=$(mk); G "$d" init -q -b main 2>/dev/null || G "$d" init -q; printf '%s' "$d"; }

echo "== Запуск Python (py.sh)"
out=$(PYX -c 'print(6 * 7)' | crlf)
[ "$out" = 42 ] && ok "py.sh: нашёл настоящий Python" || bad "py.sh: Python не найден или не запустился ($out)"
out=$(PYX -c 'import sys; print(sys.flags.utf8_mode)' | crlf)
[ "$out" = 1 ] && ok "py.sh: включает режим UTF-8" || bad "py.sh: режим UTF-8 не включён ($out)"
out=$(printf 'привет ✅' | PYX -c 'import sys; print(sys.stdin.read()[::-1])' | crlf)
[ "$out" = "✅ тевирп" ] && ok "py.sh: русские буквы и значки идут через Python без порчи" || bad "py.sh: русский текст испорчен ($out)"

# Заглушка python/python3/py (как у магазина Microsoft): печатает совет и выходит с ошибкой
S=$(mk)
for n in python python3 py; do
  printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store."\nexit 9\n' > "$S/$n"
  chmod +x "$S/$n"
done
out=$(PATH="$S:$PATH" PYX -c 'print(6 * 7)' | crlf)
[ "$out" = 42 ] && ok "py.sh: заглушки python, python3 и py впереди пути не мешают" || bad "py.sh: заглушка сломала запуск ($out)"
T=$(mkrepo); echo "KEY=1" > "$T/.env"
check 2 "заглушка Python впереди: git add .env всё равно блокируется" \
  env PATH="$S:$PATH" bash -c 'printf "%s" "$1" | (cd "$2" && bash "$3/py.sh" "$4/block-env-commit.py")' _ "$(J 'git add .env' "$(mixed "$T")")" "$T" "$H" "$HM"

# Python нет совсем: путь поиска — только заглушки. Только встроенные команды bash, поэтому py.sh справится.
BASHX=$(command -v bash)
NOPY() { PATH="$S" LOCALAPPDATA=/nonexistent PROGRAMFILES=/nonexistent "$BASHX" "$H/py.sh" "$@"; }
printf '%s' "$(J 'git add .env' "$(mixed "$T")")" | NOPY "$HM/block-env-commit.py" >/dev/null 2>&1; code=$?
[ "$code" -eq 2 ] && ok "нет Python: сохранение в git (git add) блокируется, не проходит молча" || bad "нет Python: git add прошёл мимо охраны (код $code)"
err=$(printf '%s' "$(J 'git commit -m x' "$(mixed "$T")")" | NOPY "$HM/verify-gate.py" 2>&1 >/dev/null)
echo "$err" | grep -q "Python" && ok "нет Python: человеку и Claude сказано простыми словами, что не так" || bad "нет Python: сообщения нет"
printf '%s' "$(J 'ls' "$(mixed "$T")")" | NOPY "$HM/block-env-commit.py" >/dev/null 2>&1; code=$?
[ "$code" -eq 1 ] && ok "нет Python: обычная команда не ломается, но об охране сказано (код 1)" || bad "нет Python: обычная команда получила код $code"
err=$(printf '%s' "$(J 'git status' "$(mixed "$T")" PostToolUse)" | NOPY "$HM/verify-evidence.py" 2>&1 >/dev/null)
echo "$err" | grep -q "Python" && ok "нет Python: проверка после команды тоже говорит об этом" || bad "нет Python: проверка после команды молчит"

echo "== hooks.json: команды как их запускает Claude Code"
HJ="$HM/hooks.json"
cmds=$(PYX - "$HJ" <<'PY' | crlf
import json, sys
for ev, groups in json.load(open(sys.argv[1], encoding="utf-8"))["hooks"].items():
    for g in groups:
        for h in g["hooks"]:
            print(ev, g.get("matcher", ""), h["command"], sep="\t")
PY
)
[ -n "$cmds" ] && ok "hooks.json читается" || bad "hooks.json не читается"
echo "$cmds" | grep -q $'^PreToolUse\tPowerShell\t' && ok "hooks.json: PowerShell — второй рубеж у проверки .env и «готово = доказано»" || bad "hooks.json: нет сторожей на PowerShell"
echo "$cmds" | grep -q $'^PostToolUse\tBash|PowerShell\t' && ok "hooks.json: после команды PowerShell тоже смотрим" || bad "hooks.json: после PowerShell сторож молчит"
if echo "$cmds" | cut -f3 | grep -v 'py\.sh' | grep -q 'python'; then bad "hooks.json: есть вызов python мимо py.sh"; else ok "hooks.json: каждый Python зовётся через py.sh"; fi
# Подстановка пути пакета в двух видах: C:/Users/... (так подставляет Claude Code) и C:\Users\...
precmd=$(echo "$cmds" | grep $'^PreToolUse\tBash\t' | head -1 | cut -f3)
runcmd() { local cmd=${precmd//\$\{CLAUDE_PLUGIN_ROOT\}/$1}; printf '%s' "$2" | (cd "$3" && bash -c "$cmd"); }
OSNM="$(mixed "$OSN")"
check 2 "хук как в hooks.json (путь C:/...): git add .env блокируется" runcmd "$OSNM" "$(J 'git add .env' "$(mixed "$T")")" "$T"
if [ "$WIN" = 1 ]; then
  check 2 "хук как в hooks.json (путь C:\\...): git add .env блокируется" runcmd "$(native "$OSN")" "$(J 'git add .env' "$(native "$T")")" "$T"
fi

echo "== block-env-commit: .env в git нельзя, шаблон можно"
be() { run block-env-commit.py "$(J "$1" "$2" "${3:-PreToolUse}" "${4:-Bash}")" "$2"; }
T=$(mkrepo); echo "KEY=1" > "$T/.env.production"
check 2 "env: git add .env.production блокируется" be "git add .env.production" "$T"
T=$(mkrepo); echo "KEY=" > "$T/.env.example"
check 0 "env: .env.example пропускается" be "git add .env.example" "$T"
check 0 "env: слово .env в описании коммита — не тревога" be "git commit -m 'убрал .env из git add'" "$T"
T=$(mkrepo); echo "KEY=1" > "$T/.env"; G "$T" add -f .env; G "$T" commit -qm x
check 2 "env: .env уже в git — любой коммит блокируется" be "git commit -am y" "$T"
T=$(mkrepo); mkdir "$T/app"; echo "KEY=1" > "$T/app/.env"
check 2 "env: .env без .gitignore — git add папки блокируется" be "git add app" "$T"
echo ".env" > "$T/.gitignore"
check 0 "env: .env закрыт .gitignore — git add . пропускается" be "git add ." "$T"
check 2 "env: git add -f папки с закрытым .env блокируется" be "git add -f app" "$T"
check 2 "env: сокращение --forc тоже ловится" be "git add --forc 'app'" "$T"
check 2 "env: -f у соседней команды — блок с запасом (раздели команды)" be "rm -f tmp.txt && git add ." "$T"
check 2 "env: update-index при закрытом .env блокируется" be "git update-index --add app/x" "$T"
check 0 "env: обычное добавление при закрытом .env проходит" be "git add app/main.py" "$T"
G "$T" add -f app/.env
check 2 "env: после команды .env в индексе — Claude сразу предупреждён" be "git add -A" "$T" PostToolUse
G "$T" commit -qm leak
check 2 "env: .env в git — отправка на GitHub заблокирована" be "git push" "$T"

echo "== block-env-commit: Windows (регистр, слэши, русские папки, PowerShell)"
T=$(mkrepo); echo "KEY=1" > "$T/.ENV"
check 2 "env: .ENV большими буквами — git add блокируется" be "git add ." "$T"
T=$(mkrepo); mkdir "$T/app"; echo "KEY=1" > "$T/app/.Env.Local"
check 2 "env: .Env.Local в другом регистре блокируется" be "git add app" "$T"
T=$(mkrepo); echo "KEY=" > "$T/.ENV.EXAMPLE"
check 0 "env: .ENV.EXAMPLE (образец) пропускается" be "git add ." "$T"
T=$(mkrepo); echo "KEY=1" > "$T/.ENV"; G "$T" add -f .ENV; G "$T" commit -qm x
check 2 "env: отслеживаемый .ENV блокирует коммит" be "git commit -am y" "$T"
PYX - "$HM/block-env-commit.py" <<'PY' >/dev/null 2>&1 && ok "env: пути с обратными слэшами и разным регистром распознаются как .env" || bad "env: путь Windows не распознан"
import importlib.util
import sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
yes = ["app\\.env", "App\\.ENV.local", "C:/x/.Env", ".env.", ".env.production", "\"a/.env\""]
no = ["app\\.env.example", ".ENV.SAMPLE", ".envrc", "environment.py", "x/.env.template", "a.env.dist"]
assert all(m.is_secret_env(p) for p in yes), [p for p in yes if not m.is_secret_env(p)]
assert not any(m.is_secret_env(p) for p in no), [p for p in no if m.is_secret_env(p)]
PY
PYX - "$HM" <<'PY' >/dev/null 2>&1 && ok "пути /c/Users/..., C:\\Users\\... и C:/Users/... приводятся к понятному Python виду" || bad "пути Windows приводятся неверно"
import importlib.util
import sys
def load(name, file):
    spec = importlib.util.spec_from_file_location(name, f"{sys.argv[1]}/{file}")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
for m, fn in ((load("b", "block-env-commit.py"), "fix_cwd"), (load("v", "verify-gate.py"), "fix_cwd"),
              (load("l", "lint-after-edit.py"), "win_path")):
    f = getattr(m, fn)
    assert f("/c/Users/Иван Петров/проект", win=True) == "C:/Users/Иван Петров/проект", fn
    assert f("/cygdrive/d/a", win=True) == "D:/a", fn
    assert f("/c", win=True) == "C:/", fn
    assert f("/tmp/x", win=True) == "/tmp/x", fn
    assert f("C:\\work\\x", win=True) == "C:\\work\\x", fn
    assert f("C:/work/x", win=True) == "C:/work/x", fn
    assert f("/c/work/x", win=False) == "/c/work/x", fn
PY
if [ "$WIN" = 1 ]; then
  T=$(mkrepo); echo "KEY=1" > "$T/.env"
  check 2 "охрана: папка в виде C:/Users/... — git add .env блокируется" be "git add .env" "$(mixed "$T")"
  check 2 "охрана: папка в виде C:\\Users\\... — git add .env блокируется" be "git add .env" "$(native "$T")"
  check 2 "охрана: папка в виде /c/Users/... — git add .env блокируется" be "git add .env" "$(posix "$T")"
fi
T="$(mk)/Иван Петров/проект"; mkdir -p "$T"; G "$T" init -q; echo "KEY=1" > "$T/.env"
check 2 "охрана: русские буквы и пробел в пути папки не мешают" be "git add .env" "$(native "$T")"
check 2 "охрана: русская команда не ломает проверку" be "git commit -m 'Исправил Ищем'" "$(native "$T")"
echo ".env" > "$T/.gitignore"
check 0 "охрана: закрытый .env в русской папке не мешает" be "git add ." "$(native "$T")"
T=$(mkrepo); echo "KEY=1" > "$T/.env"
check 2 "PowerShell: git add .env блокируется" be "git add .env" "$T" PreToolUse PowerShell
check 2 "PowerShell: git.exe add -A с .env в проекте блокируется" be '& git.exe add -A' "$T" PreToolUse PowerShell
check 2 "PowerShell: git и add через ; после другой команды тоже ловится" be 'cd app; git add -A' "$T" PreToolUse PowerShell
echo ".env" > "$T/.gitignore"
check 2 "PowerShell: git add -f при закрытом .env блокируется" be 'git add -f .' "$T" PreToolUse PowerShell
check 0 "PowerShell: обычная команда не мешает" be 'Get-ChildItem' "$T" PreToolUse PowerShell

echo "== block-env-commit: git пишет не в папку сеанса (cd, -C, --git-dir, --work-tree, Set-Location)"
# hk <команда> <папка> [инструмент] — хук до команды; JSON собирает Python (J не экранирует переносы строк)
hk() { local json; json=$(HK_CMD="$1" HK_DIR="$2" HK_TOOL="${3:-Bash}" PYX -c 'import json, os; print(json.dumps({
  "hook_event_name": "PreToolUse", "tool_name": os.environ["HK_TOOL"], "tool_input": {"command": os.environ["HK_CMD"]},
  "cwd": os.environ["HK_DIR"]}))' | crlf); run block-env-commit.py "$json" "$2"; }
# why <часть текста> <описание> <команда> <папка> [инструмент] — блок именно по этой причине, а не по соседней
why() { local err got; err=$(hk "$3" "$4" "${5:-Bash}" 2>&1 >/dev/null); got=$?
        [ "$got" -eq 2 ] && [[ "$err" == *"$1"* ]] && ok "$2" || bad "$2 (код $got)"; }
E="не закрыты .gitignore"; U="не понял, в какой папке"; N="репозитория ещё нет"
T=$(mk); mkdir "$T/proj"; G "$T/proj" init -q; echo "KEY=1" > "$T/proj/.env"
why "$E" "цель: git -C папка add — проверяется та папка, не папка сеанса" 'git -C proj add .env' "$T"
why "$E" "цель: cd папка && git add — тоже" 'cd proj && git add .' "$T"
why "$E" "цель: --git-dir= и --work-tree= — тоже" 'git --git-dir=proj/.git --work-tree=proj add .env' "$T"
why "$E" "цель: Git Bash, путь вида /c/... в cd — тоже" "cd '$(posix "$T/proj")' && git add ." "$T"
why "$E" "цель: PowerShell, Set-Location папка — тоже" 'Set-Location proj; git add -A' "$T" PowerShell
why "$E" "цель: PowerShell, полный путь с обратными слэшами — тоже" "cd '$(native "$T/proj")'; & git.exe add -A" "$T" PowerShell
why "$E" "цель: powershell -Command из Git Bash — тоже" 'powershell.exe -NoProfile -Command "cd proj; git add ."' "$T"
why "$E" "цель: комментарий в конце строки не съедает следующий cd" "$(printf 'git status # check\ncd proj\ngit add .')" "$T" PowerShell
why "$U" 'цель: путь через переменную ($env:P) — не узнать, блок' 'git -C $env:P add .' "$T" PowerShell
why "$U" 'цель: $env:GIT_DIR — не узнать, блок' '$env:GIT_DIR = "proj/.git"; git add .env' "$T" PowerShell
why "$N" "цель: git add туда, где репозитория до команды нет (git init там же), — блок" 'cd newp; git init; git add .' "$T" PowerShell
echo ".env" > "$T/proj/.gitignore"
check 0 "цель: в той папке .env закрыт — cd папка && git add проходит" be 'cd proj && git add . && git commit -m "cd x; ok"' "$T"
check 0 "цель: PowerShell, полный путь с обратными слэшами понят — проходит" be "cd '$(native "$T/proj")'; git add -A" "$T" PreToolUse PowerShell
check 0 "цель: описание коммита @'…'@ с апострофом не мешает" hk "$(printf "cd proj; git commit -m @'\nit's ok\n'@")" "$T" PowerShell
check 0 "цель: перенос строки через обратную кавычку в PowerShell не мешает" hk "$(printf 'git -C `\n  proj add -A')" "$T" PowerShell
# чужое репо с «фильтром» в настройках: сторож его не запускает (git status запустил бы)
T=$(mkrepo); M="$ROOTTMP/lovushka-metka"
echo '*.txt filter=lovushka' > "$T/.gitattributes"; G "$T" config filter.lovushka.clean "touch '$M'; cat"
echo a > "$T/a.txt"; G "$T" add a.txt .gitattributes; G "$T" commit -qm a; rm -f "$M"; echo b > "$T/a.txt"
check 0 "чужое репо с фильтром: проверка проходит" be 'git add a.txt' "$T"
[ ! -e "$M" ] && ok "фильтр из настроек чужого репо сторож не запускает" || bad "сторож запустил фильтр чужого репо"

echo "== Охрана: имя git в любом регистре, git только по полному пути, сбой git"
T=$(mkrepo); echo "KEY=1" > "$T/.env"
check 2 "регистр: Git.exe add .env блокируется (Windows не различает регистр имени)" be "Git.exe add .env" "$T"
check 2 "регистр: GIT COMMIT -am x с .env в проекте блокируется" be "GIT COMMIT -am x" "$T"
check 2 "регистр: PowerShell, & GIT.EXE add -A с .env блокируется" be '& GIT.EXE add -A' "$T" PreToolUse PowerShell
T=$(mkrepo); echo "x = 1" > "$T/a.py"
out=$(run verify-gate.py "$(J 'Git.exe commit -m x' "$(mixed "$T")" | sed "s/^{/{\"session_id\":\"case-$$\",/")" "$T")
echo "$out" | grep -q '"block"' && ok "gate: Git.exe commit (другой регистр) тоже требует проверки" || bad "gate: Git.exe commit проскочил мимо «готово = доказано»"
echo "$(PYX -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["PreToolUse"]))' "$HJ" | crlf)" | grep -q '"if"' \
  && bad "hooks.json: у сторожа есть фильтр if (он различает регистр и пропустит Git.exe)" || ok "hooks.json: сторож смотрит каждую команду, фильтра if нет"
printf '%s' "$(J 'GIT commit -m x' "$(mixed "$T")")" | NOPY "$HM/block-env-commit.py" >/dev/null 2>&1; code=$?
[ "$code" -eq 2 ] && ok "нет Python: GIT commit большими буквами тоже блокируется" || bad "нет Python: GIT commit прошёл мимо охраны (код $code)"

# Подложенный в проект git не запускается. Windows ищет голое имя сначала в текущей папке, а хук работает в папке проекта.
# Пустышка пишет метку-файл и ничего не печатает: запусти хук её, охрана .env была бы обойдена (git «ответил» пустым списком).
T=$(mkrepo); echo "KEY=1" > "$T/.env"                          # .env не закрыт .gitignore: настоящая охрана git add блокирует
MARK="$ROOTTMP/podmena-metka"
if [ "$WIN" = 1 ]; then
  cat > "$ROOTTMP/podmena.cs" <<'CS'
using System;
using System.IO;
public static class Podmena {
    public static int Main(string[] args) {
        File.WriteAllText(Environment.GetEnvironmentVariable("PODMENA_METKA"), "x");
        return 0;
    }
}
CS
  powershell.exe -NoProfile -NonInteractive -Command "Add-Type -Path '$(native "$ROOTTMP")\\podmena.cs' -OutputAssembly '$(native "$T")\\git.exe' -OutputType ConsoleApplication" >"$ROOTTMP/csc.out" 2>&1
  PODMENA_METKA="$(native "$MARK")" "$T/git.exe" >/dev/null 2>&1
  if [ -e "$MARK" ]; then ok "подмена git: пустышка git.exe собрана и сама работает"; else bad "подмена git: пустышка не собралась, проверка не имеет смысла"; head -5 "$ROOTTMP/csc.out"; fi
  PFXS=("")
else
  printf '#!/bin/sh\n: > "$PODMENA_METKA"\nexit 0\n' > "$T/git"; chmod +x "$T/git"
  PFXS=(".:" ":" "$T:")                                           # «.», пусто и сама папка проекта в начале PATH
fi
[ "$WIN" = 1 ] && PFXS+=("$(cygpath -u "$T"):")
for pfx in "${PFXS[@]}"; do
  rm -f "$MARK"
  printf '%s' "$(J 'git add .' "$(mixed "$T")")" | (cd "$T" && PODMENA_METKA="$(native "$MARK")" PATH="$pfx$PATH" bash "$H/py.sh" "$HM/block-env-commit.py") >/dev/null 2>&1; code=$?
  if [ -e "$MARK" ]; then bad "подмена git: хук запустил git из папки проекта (начало PATH: «${pfx}»)"
  elif [ "$code" -ne 2 ]; then bad "подмена git: охрана .env обойдена (код $code, начало PATH: «${pfx}»)"
  else ok "подмена git: git из папки проекта не запущен, охрана .env сработала (начало PATH: «${pfx:-пусто}»)"; fi
  rm -f "$MARK"
  printf '%s' "$(J 'git commit -m x' "$(mixed "$T")" | sed "s/^{/{\"session_id\":\"podmena-$$\",/")" | (cd "$T" && PODMENA_METKA="$(native "$MARK")" PATH="$pfx$PATH" bash "$H/py.sh" "$HM/verify-gate.py") >/dev/null 2>&1
  [ -e "$MARK" ] && bad "подмена git: verify-gate запустил git из папки проекта (начало PATH: «${pfx}»)" || ok "подмена git: verify-gate git из папки проекта не запускает"
done
# git совсем нет (Python есть): запись в git блокируется с понятным текстом, остальные команды работают
PYEXE=$(PYX -c 'import sys; print(sys.executable)' | crlf)
NG=$(mk)
if [ "$WIN" = 1 ]; then NGP="$(dirname "$(cygpath -u "$PYEXE")")"; else ln -s "$PYEXE" "$NG/python"; NGP="$NG"; fi
T=$(mkrepo)
nogit() { printf '%s' "$(J "$1" "$(mixed "$T")")" | (cd "$T" && env "ProgramFiles=/nonexistent" "ProgramW6432=/nonexistent" "ProgramFiles(x86)=/nonexistent" "LOCALAPPDATA=/nonexistent" PATH="$NGP" "$BASHX" "$H/py.sh" "$HM/block-env-commit.py"); }
err=$(nogit 'git add .' 2>&1 >/dev/null); code=$?
[ "$code" -eq 2 ] && echo "$err" | grep -q "git" && ok "нет git: запись в git (git add) блокируется с пояснением, а не пропускается" || bad "нет git: git add прошёл или без пояснения (код $code)"
nogit 'git push' >/dev/null 2>&1; code=$?
[ "$code" -eq 2 ] && ok "нет git: отправка (git push) блокируется" || bad "нет git: git push прошёл (код $code)"
nogit 'ls -la' >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] && ok "нет git: обычная команда не мешает" || bad "нет git: обычная команда получила код $code"
nogit 'git status' >/dev/null 2>&1; code=$?
[ "$code" -eq 0 ] && ok "нет git: git status (не запись) не блокируется" || bad "нет git: git status получил код $code"

echo "== .env-public (публичные переменные)"
T=$(mkrepo); mkdir "$T/web"; echo "VITE_API_URL=https://example.com" > "$T/web/.env.production"
G "$T" add -f web/.env.production; G "$T" commit -qm site
check 2 "env: публичный .env без исключения — блок" be "git commit -am y" "$T"
printf '# только публичные\r\nweb/.env.production\r\n' > "$T/.env-public"
check 0 "env: .env-public с концами строк CRLF — коммит проходит" be "git commit -am y" "$T"
if [ "$WIN" = 1 ]; then
  printf 'web\\.env.production\r\n' > "$T/.env-public"
  check 0 "env: .env-public с путём через обратный слэш — коммит проходит" be "git commit -am y" "$T"
fi
printf '\xef\xbb\xbfweb/.env.production\n' > "$T/.env-public"
check 0 "env: .env-public с меткой BOM (Блокнот) читается" be "git commit -am y" "$T"
printf 'web/.env.production\n' > "$T/.env-public"
check 0 "env: исключение — страховка после команды молчит" be "git status" "$T" PostToolUse
echo "API_SECRET=x" >> "$T/web/.env.production"
check 2 "env: в исключение дописали секрет — снова блок" be "git push" "$T"
printf 'VITE_API_URL=https://example.com\nSECRETVALUE\n' > "$T/web/.env.production"
check 2 "env: строка без = в исключении — блок" be "git push" "$T"
printf 'VITE_A=\xff\xfe\n' > "$T/web/.env.production"
check 2 "env: непонятная кодировка — исключение не действует (не падение)" be "git push" "$T"
printf '../outside/.env\n' > "$T/.env-public"
check 2 "env: путь за пределы репо в списке — не исключение" be "git push" "$T"
printf 'C:/Windows/.env\n' > "$T/.env-public"
check 2 "env: путь с диска в списке — не исключение" be "git push" "$T"
T=$(mkrepo); mkdir "$T/web"; printf 'web/.env.production\n' > "$T/.env-public"
printf 'VITE_A=1\nAPI_SECRET=x\n' > "$T/web/.env.production"; G "$T" add -f web/.env.production; G "$T" commit -qm a
echo "VITE_A=1" > "$T/web/.env.production"; G "$T" add -f web/.env.production; G "$T" commit -qm b
check 2 "env: секрет в неотправленной истории — отправка заблокирована" be "git push" "$T"

echo "== verify-gate + verify-evidence: «готово = доказано»"
LOGDIR=$(PYX -c 'import tempfile; print(tempfile.gettempdir())' | crlf)
vg() { run verify-gate.py "$(J "git commit -m x" "$1" PreToolUse "${2:-Bash}" | sed "s/^{/{\"session_id\":\"$SID\",/")" "$1"; }
ev() { run verify-evidence.py "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"${3:-Bash}\",\"tool_input\":{\"command\":\"$(jesc "$1")\"},\"session_id\":\"$SID\"}" "$2"; }
T=$(mkrepo); echo "x = 1" > "$T/a.py"
blocked() { vg "$@" | grep -q '"block"'; }
blocked "$(mixed "$T")" && ok "gate: коммит кода без проверки блокируется" || bad "gate: коммит без проверки прошёл"
blocked "$(mixed "$T")" PowerShell && ok "gate: то же через PowerShell" || bad "gate: через PowerShell коммит без проверки прошёл"
# что считается проверкой на Windows
while IFS= read -r line; do
  cmd="${line%%|*}"; what="${line#*|}"
  ev "$cmd" "$T"
  [ -z "$(vg "$(mixed "$T")")" ] && ok "gate: $what — улика" || bad "gate: $what не засчитан"
  blocked "$(mixed "$T")" && ok "gate: улика расходуется, следующий коммит снова требует" || bad "gate: улика не израсходована ($what)"
done <<'EOF'
python a.py|запуск python
python.exe a.py|запуск python.exe
.venv/Scripts/python.exe obrabotka.py|запуск из .venv/Scripts
.venv\Scripts\python.exe obrabotka.py|запуск из .venv\Scripts (обратные слэши)
PYTHON A.PY|запуск в другом регистре
py -3 a.py|запуск через py -3
bash plugins/osnova/hooks/py.sh a.py|запуск через py.sh
curl.exe https://example.com|curl.exe
bash scripts/check.sh|прогон check.sh
EOF
ev "bash plugins/osnova/hooks/py.sh -c ''" "$T"
blocked "$(mixed "$T")" && ok "gate: просто упоминание py.sh без скрипта — не проверка" || bad "gate: py.sh без скрипта засчитан как проверка"
ev "git commit -m 'python a.py'" "$T"
blocked "$(mixed "$T")" && ok "gate: сам коммит с «python a.py» в тексте — не проверка" || bad "gate: коммит засчитан как проверка"
ev 'python a.py' "$T" PowerShell
[ -z "$(vg "$(mixed "$T")" PowerShell)" ] && ok "gate: проверка из PowerShell засчитывается" || bad "gate: проверка из PowerShell не засчитана"
printf '%s' "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"C:\\\\x\\\\Скриншот.PNG\"},\"session_id\":\"$SID\"}" | PYX "$HM/verify-evidence.py" >/dev/null 2>&1
[ -z "$(vg "$(mixed "$T")")" ] && ok "gate: скриншот Скриншот.PNG (большими буквами) — улика" || bad "gate: скриншот в верхнем регистре не засчитан"
rm -f "$T/a.py"; echo "# заметка" > "$T/README.MD"
[ -z "$(vg "$(mixed "$T")")" ] && ok "gate: только документы (README.MD) — без проверки" || bad "gate: документы заблокированы"
echo "x = 1" > "$T/a.py"
out=$(run verify-gate.py "$(J 'VERIFY_OK=1 git commit -m x' "$(mixed "$T")")" "$T")
[ -z "$out" ] && ok "gate: VERIFY_OK=1 — осознанный пропуск" || bad "gate: VERIFY_OK=1 не сработал"
out=$(run verify-gate.py "$(J '$env:VERIFY_OK=1; git commit -m x' "$(mixed "$T")" PreToolUse PowerShell)" "$T")
[ -z "$out" ] && ok "gate: VERIFY_OK=1 в записи PowerShell — осознанный пропуск" || bad "gate: VERIFY_OK=1 из PowerShell не сработал"
if [ "$WIN" = 1 ]; then
  out=$(run verify-gate.py "$(J 'git commit -m x' "$(posix "$T")" | sed "s/^{/{\"session_id\":\"$SID\",/")" "$T")
  echo "$out" | grep -q '"block"' && ok "gate: папка в виде /c/Users/... понята (коммит без проверки блокируется)" || bad "gate: папка /c/Users/... не понята"
fi

echo "== lint-after-edit: сломанный код возвращается Claude"
PROBE=$(PYX - "$HM/lint-after-edit.py" <<'PY' | crlf
import importlib.util
import sys
spec = importlib.util.spec_from_file_location("lint", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print("ruff=" + (m.system_tool("ruff") or ""), "node=" + (m.system_tool("node") or ""))
PY
)
lint() { run lint-after-edit.py "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$(jesc "$1")\"}}" "${2:-.}"; }
T=$(mk)
case "$PROBE" in *"node=/"*|*"node=C:"*|*"node=D:"*)
  echo "function (" > "$T/bad.js"; echo "const a = 1;" > "$T/ok.js"
  check 2 "lint: сломанный js ловится" lint "$(mixed "$T")/bad.js"
  check 0 "lint: целый js проходит" lint "$(mixed "$T")/ok.js"
  cp "$T/bad.js" "$T/BAD2.JS"
  check 2 "lint: расширение большими буквами (BAD2.JS) тоже проверяется" lint "$(mixed "$T")/BAD2.JS"
  if [ "$WIN" = 1 ]; then
    check 2 "lint: путь файла C:\\Users\\... (как шлёт Claude Code) понят" lint "$(native "$T")\\bad.js"
    check 2 "lint: путь файла /c/Users/... понят" lint "$(posix "$T")/bad.js"
  fi ;;
*) skip "lint js (нет доверенного node)" ;;
esac
case "$PROBE" in *"ruff=/"*|*"ruff=C:"*|*"ruff=D:"*)
  printf 'import os\nprint(undefined_name)\n' > "$T/bad.py"; printf 'print("ok")\n' > "$T/good.py"
  check 2 "lint: ruff находит ошибку в .py" lint "$(mixed "$T")/bad.py"
  check 0 "lint: хороший .py проходит" lint "$(mixed "$T")/good.py"
  [ "$WIN" = 1 ] && check 2 "lint: ruff читает путь файла C:\\Users\\..." lint "$(native "$T")\\bad.py" ;;
*) skip "lint python (нет ruff в ~/.local/bin)" ;;
esac
# подложенные в проект программы не запускаются, из ~/.local/bin доверяем только ruff
PYX - "$HM/lint-after-edit.py" <<'PY' >/dev/null 2>&1 && ok "lint: из ~/.local/bin доверяем только ruff; папка проекта и чужой node не запускаются" || bad "lint: доверие к папкам не то"
import importlib.util
import os
import sys
import tempfile
spec = importlib.util.spec_from_file_location("lint", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
t = os.path.realpath(tempfile.mkdtemp())
ext = ".exe" if m.IS_WIN else ""
for name in ("ruff", "node", "tsc"):
    path = os.path.join(t, name + ext)
    open(path, "w").close()
    os.chmod(path, 0o755)
m.USER_BIN, m.CLEAN_PATH = t, "" if m.IS_WIN else "/nonexistent"
assert m.system_tool("ruff") == os.path.join(t, "ruff" + ext), m.system_tool("ruff")
assert not m.system_tool("node") and not m.system_tool("tsc")
# папка сеанса: программа внутри неё не запускается, даже если лежит в «доверенном» месте
os.chdir(t)
assert not m.system_tool("ruff"), "ruff из папки сеанса запущен"
if m.IS_WIN:
    assert m.under("C:\\Users\\X\\.local\\bin\\ruff.exe", "c:\\users\\x\\.local\\bin")
PY

echo "== session-start: правила и состояние человека"
D=$(mk); PR=$(mk); OTHER=$(mk)
ss() { # ss [папка сеанса] — со всеми настройками установки
  CLAUDE_PLUGIN_DATA="$(native "$D")" CLAUDE_PLUGIN_ROOT="${SSROOT:-$(mixed "$OSN")}" CLAUDE_PROJECT_DIR="$(native "${1:-$OTHER}")" \
    PYTHONUTF8="${SS_UTF8-1}" CLAUDE_CODE_USE_POWERSHELL_TOOL="${SS_PS-0}" bash "$H/session-start.sh" 2>/dev/null; }
out=$(ss)
first=$(head -1 "$OSN/rules/PRAVILA.md" | crlf)
echo "$out" | grep -qF "$first" && ok "start: правила пакета подмешиваются в сеанс" || bad "start: правила не подмешались"
echo "$out" | grep -q 'hooks/py.sh' && ok "start: сказано, чем запускать Python (py.sh)" || bad "start: нет подсказки про py.sh"
echo "$out" | grep -q "Охрана пакета сейчас НЕ работает" && bad "start: ложная тревога про охрану" || ok "start: охрана в порядке — без тревоги"
echo "$out" | grep -q "Настройки Windows" && bad "start: ложная тревога про настройки" || ok "start: настройки на месте — без тревоги"
echo "$out" | grep -qi "xcode\|Apple" && bad "start: говорит про Apple" || ok "start: без советов про Apple"
echo "$out" | grep -q "Первый запуск" && ok "start: новичку — проводник" || bad "start: первый запуск не замечен"
[ -f "$D/stroka.py" ] && ok "start: строка внизу окна лежит в постоянной папке" || bad "start: строка не скопирована"
if [ "$WIN" = 1 ]; then
  out=$(SSROOT="$(native "$OSN")" ss); echo "$out" | grep -q 'hooks/py.sh' && ok "start: путь пакета с обратными слэшами понят" || bad "start: путь пакета C:\\... не понят"
fi
out=$(SS_PS=1 ss)
echo "$out" | grep -q "Настройки Windows не закончены" && echo "$out" | grep -q "PowerShell" \
  && ok "start: включённый PowerShell замечен и назван" || bad "start: включённый PowerShell не замечен"
out=$(SS_PS= ss)
echo "$out" | grep -q "PowerShell" && ok "start: переменная PowerShell не задана — тоже предупреждение" || bad "start: незаданная переменная не замечена"
out=$(SS_UTF8= ss)
echo "$out" | grep -q "PYTHONUTF8" && ok "start: нет PYTHONUTF8 — предупреждение" || bad "start: PYTHONUTF8 не проверяется"
CP=$(mk); cp -R "$OSN/." "$CP/"; printf '#!/bin/bash\nexit 1\n' > "$CP/hooks/py.sh"
out=$(SSROOT="$(mixed "$CP")" ss)
echo "$out" | grep -q "Охрана пакета сейчас НЕ работает" && echo "$out" | grep -q "Python" \
  && ok "start: нет Python — громкая тревога" || bad "start: отсутствие Python не замечено"

touch "$D/gotovo"
new=$(sed -n 's/.*"versiya": *\([0-9][0-9]*\).*/\1/p' "$OSN/skills/start/nastroyki.json" | head -1 | crlf)
printf '%s\r\n' "${new:-0}" > "$D/nastroyki-versiya"
out=$(ss)
! echo "$out" | grep -qE "Первый запуск|обновил настройки|заведён|ждёт" && ok "start: пройденный проводник, файл состояния с \\r\\n — без напоминаний" || bad "start: лишние напоминания (\\r\\n в файле состояния?)"
echo 0 > "$D/nastroyki-versiya"; printf '%s\r\n' "$(native "$PR")" > "$D/sprosit-zadachu"
out=$(ss "$PR")
echo "$out" | grep -q "Автор обновил настройки" && ok "start: устаревшие настройки — предложить обновить" || bad "start: устаревшие настройки не замечены"
echo "$out" | grep -q "только что заведён" && echo "$out" | grep -q "Что хотите сделать" \
  && ok "start: в папке нового проекта (путь C:\\... с \\r\\n в файле) — спросить задачу" || bad "start: не спросил задачу"
n=$(printf '%s' "$out" | PYX -c 'import sys; print(len(sys.stdin.read()))' | crlf)
[ "$n" -lt 10000 ] && ok "start: всё вместе влезает в предел 10 000 знаков ($n)" || bad "start: вывод $n знаков — Claude увидит обрезок"
out=$(SS_PS=1 SS_UTF8= SSROOT="$(mixed "$CP")" ss "$PR")
n=$(printf '%s' "$out" | PYX -c 'import sys; print(len(sys.stdin.read()))' | crlf)
[ "$n" -lt 10000 ] && ok "start: даже со всеми тревогами влезает в предел ($n)" || bad "start: со всеми тревогами вывод $n знаков"
out=$(ss "$PR"); ! echo "$out" | grep -q "только что заведён" && ok "start: «спросить задачу» — один раз" || bad "start: спрашивает задачу каждый сеанс"
printf '%s\r\n' "$(native "$PR")" > "$D/sprosit-zadachu"; printf 'бот для кофейни\r\n' > "$D/zadacha"; out=$(ss "$PR")
echo "$out" | grep -q "назвал задачу: «бот для кофейни»" && ! echo "$out" | grep -q "Что хотите сделать" && [ ! -f "$D/zadacha" ] \
  && ok "start: задача, названная до настройки, — напомнить, не спрашивать заново" || bad "start: задача до настройки потерялась"
printf '%s\n' "$(native "$PR")" > "$D/sprosit-zadachu"
out=$(ss)  # (в переменную, а не в grep -q: тот закрывает трубу раньше, чем скрипт допишет правила, и pipefail ругается)
echo "$out" | grep -q "Новый проект ждёт" && [ -f "$D/sprosit-zadachu" ] && ok "start: сеанс в другой папке подсказывает и метку не тратит" || bad "start: чужой сеанс потратил метку"
echo "$out" | grep -q 'cd .*; claude' && ok "start: подсказка для человека через ; (не &&)" || bad "start: подсказка не через ;"

echo "== Скелет проекта: концы строк и сторож ключей"
if [ "$WIN" = 1 ]; then
  K=$(mk); git -c core.autocrlf=true clone -q "$REPO" "$K/k" 2>/dev/null
  bad_files=$(PYX - "$K/k/plugins/osnova" <<'PY' | crlf
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
for sub in ("hooks", "skelet"):
    for p in sorted((root / sub).rglob("*")):
        if p.is_file() and b"\r" in p.read_bytes():
            print(p.relative_to(root).as_posix())
PY
)
  [ -z "$bad_files" ] && ok "концы строк: пакет скачан с core.autocrlf=true — хуки и скелет остались с LF" || { bad "концы строк: Git испортил файлы пакета"; echo "$bad_files" | head -5; }
fi
P=$(mk); cp -R "$OSN/skelet/." "$P/"
[ -f "$P/.gitattributes" ] && grep -q 'githooks' "$P/.gitattributes" && ok "скелет: .gitattributes (LF для охраны) попадает в проект" || bad "скелет: нет .gitattributes"
G "$P" init -q -b main 2>/dev/null || G "$P" init -q
G "$P" config core.autocrlf true
G "$P" add -A; G "$P" commit -qm first --no-verify
L=$(mk); git -c core.autocrlf=true clone -q "$P" "$L/klon" 2>/dev/null
if grep -q $'\r' "$L/klon/.githooks/pre-commit"; then bad "скелет: в скачанной копии охрана pre-commit с CR — сломана"; else ok "скелет: в скачанной копии (autocrlf=true) охрана pre-commit цела"; fi
GL=""; for f in "$HOME/.local/bin/gitleaks" "$HOME/.local/bin/gitleaks.exe"; do [ -f "$f" ] && GL=1; done
command -v gitleaks >/dev/null 2>&1 && GL=1
if [ -n "$GL" ]; then
  P="$(mk)/Иван Петров/проект"; mkdir -p "$P"; cp -R "$OSN/skelet/." "$P/"
  G "$P" init -q -b main 2>/dev/null || G "$P" init -q
  G "$P" config core.hooksPath .githooks; G "$P" config core.autocrlf true
  G "$P" add -A
  G "$P" commit -qm first >/dev/null 2>&1 && ok "ключи: чистое сохранение проходит (папка с русскими буквами и пробелом)" || bad "ключи: чистое сохранение остановлено"
  # ключи-подделки: готовой строки нет ни в файлах, ни в логах — собираем при запуске
  tok="gh""p_$(PYX -c 'import random, string; print("".join(random.choice(string.ascii_letters + string.digits) for _ in range(36)))' | crlf)"
  tg="$(PYX -c 'import random, string; print(random.randint(10**9, 10**10 - 1))' | crlf):A$(PYX -c 'import random, string; print("".join(random.choice(string.ascii_letters + string.digits) for _ in range(34)))' | crlf)"
  before=$(G "$P" rev-list --count HEAD)
  printf 'TOKEN = "%s"\n' "$tok" > "$P/config.py"; G "$P" add config.py
  out=$(G "$P" commit -qm leak 2>&1); code=$?
  [ $code -ne 0 ] && [ "$(G "$P" rev-list --count HEAD)" = "$before" ] && ok "ключи: настоящий по виду ключ GitHub не сохраняется (gitleaks)" || bad "ключи: ключ GitHub сохранился"
  case "$out" in *"$tok"*) bad "ключи: значение ключа попало в сообщение сторожа" ;; *) ok "ключи: сторож не печатает значение ключа" ;; esac
  G "$P" reset -q; rm -f "$P/config.py"
  printf 'from aiogram import Bot\nbot = Bot(token="%s")\n' "$tg" > "$P/bot.py"; G "$P" add bot.py
  G "$P" commit -qm leak2 >/dev/null 2>&1; code=$?
  [ $code -ne 0 ] && ok "ключи: ключ Telegram-бота не сохраняется (правило проекта)" || bad "ключи: ключ Telegram-бота сохранился"
  G "$P" reset -q; rm -f "$P/bot.py"
  printf 'print("ok")\n' > "$P/ok.py"; G "$P" add ok.py
  G "$P" commit -qm fine >/dev/null 2>&1 && ok "ключи: после удаления секрета сохранение снова проходит" || bad "ключи: сторож не отпустил чистое сохранение"
else
  skip "ключи: сторож gitleaks в скелете (gitleaks не установлен)"
fi

exit $fail
