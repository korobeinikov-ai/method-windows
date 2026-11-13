#!/usr/bin/env bash
# Шаблон Telegram-бота и библиотеки из навыков ставятся и работают на Windows: среда, библиотеки, unittest, запуск.
# Запуск: Git Bash на Windows (главная мерка) или Mac (быстрая проверка, нужен интернет и Python 3.10+).
# Печатает ✅/❌ по шагам, при провале код 1. Ключ бота — подделка, собирается во время запуска и нигде не печатается.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$REPO/plugins/osnova"
SHABLON="$PKG/skills/telegram-bot/shablon"
fail=0; n_ok=0
ok()  { echo "✅ $1"; n_ok=$((n_ok + 1)); }
bad() { echo "❌ $1"; fail=1; }
wpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -aw "$1"; else printf '%s' "$1"; fi; }

if [ -f "$PKG/hooks/py.sh" ]; then PY=(bash "$PKG/hooks/py.sh"); else PY=(python3); fi
newpy() { "$@" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' </dev/null 2>/dev/null; }
if ! newpy "${PY[@]}"; then   # на Mac системный Python старый: берём любой новее
  for c in python3.14 python3.13 python3.12 python3.11 python3.10; do command -v "$c" >/dev/null && newpy "$c" && PY=("$c") && break; done
fi
newpy "${PY[@]}" || { echo "❌ Нужен Python 3.10 или новее: ${PY[*]}"; exit 1; }
echo "Python: $("${PY[@]}" -c 'import sys; print(sys.version.split()[0])' </dev/null | tr -d '\r')"
export PYTHONDONTWRITEBYTECODE=1 PIP_DISABLE_PIP_VERSION_CHECK=1

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# venv <папка>: среда проекта, как в навыках (Scripts на Windows, bin на Mac)
venv() {
  "${PY[@]}" -m venv "$1/.venv" </dev/null >"$T/venv.log" 2>&1 || return 1
  if [ -x "$1/.venv/Scripts/pip.exe" ]; then VPIP="$1/.venv/Scripts/pip.exe"; VPY="$1/.venv/Scripts/python.exe"
  else VPIP="$1/.venv/bin/pip"; VPY="$1/.venv/bin/python"; fi
}
# pip <описание> <аргументы...>: ставим, при провале показываем хвост журнала
pipi() {
  local what=$1; shift
  if "$VPIP" install --quiet "$@" >"$T/pip.log" 2>&1; then ok "$what"; else bad "$what"; tail -8 "$T/pip.log" | sed 's/^/    /'; return 1; fi
}

echo "== 1. Бот из шаблона: среда, библиотеки, проверка"
BOT="$T/bot"; mkdir -p "$BOT"; cp -R "$SHABLON/." "$BOT/"
if venv "$BOT"; then ok "python -m venv .venv создаёт среду"; else bad "среда .venv не создалась"; tail -5 "$T/venv.log" | sed 's/^/    /'; fi
BOTPY="$VPY"
if pipi "pip install -r requirements.txt: aiogram и openpyxl из шаблона ставятся" -r "$BOT/requirements.txt"; then
  if ( cd "$BOT" && "$BOTPY" -m unittest ) >"$T/unittest.log" 2>&1; then ok "python -m unittest в шаблоне проходит ($(grep -E '^Ran ' "$T/unittest.log" | head -1))"
  else bad "python -m unittest в шаблоне не прошёл"; tail -15 "$T/unittest.log" | sed 's/^/    /'; fi
  pipi "anthropic==0.125.0 из II.md ставится рядом с aiogram" anthropic==0.125.0 || true
  pipi "tzdata из ZADACHI.md ставится" tzdata || true
  ( cd "$BOT" && "$BOTPY" -c 'from zoneinfo import ZoneInfo; ZoneInfo("Europe/Moscow")' ) >"$T/tz.log" 2>&1 \
    && ok "часовой пояс Europe/Moscow находится (нужен tzdata)" || { bad "часовой пояс Europe/Moscow не находится"; tail -3 "$T/tz.log" | sed 's/^/    /'; }

  echo "== 2. Бот запускается на этом компьютере и не печатает ключ"
  BOT_PY="$(wpath "$BOTPY")" BOT_DIR="$(wpath "$BOT")" "${PY[@]}" - >"$T/run.out" 2>&1 <<'PYEOF'
import os, secrets, subprocess

tok = f"{secrets.randbelow(10**9) + 10**9}:A{secrets.token_urlsafe(30)}"   # ключ-подделка, нигде не печатается
env = dict(os.environ, TELEGRAM_BOT_TOKEN=tok, TELEGRAM_SVOI="1", PYTHONUTF8="1")
try:
    r = subprocess.run([os.environ["BOT_PY"], "main.py"], cwd=os.environ["BOT_DIR"], env=env, capture_output=True,
                       timeout=45)
    vyvod, kod, zavis = r.stdout + r.stderr, r.returncode, False
except subprocess.TimeoutExpired as e:   # бот ждёт ответа сети: для проверки хватит того, что он стартовал
    vyvod, kod, zavis = (e.stdout or b"") + (e.stderr or b""), None, True
tekst = vyvod.decode("utf-8", errors="replace")
kusok = tok.split(":")[1][:12]
print(("OK " if "Бот запущен, своих людей: 1" in tekst else "FAIL ") + "бот запустился и написал по-русски в журнал")
print(("OK " if kusok not in tekst else "FAIL ") + "ключа бота нет в выводе запуска (журнал, ошибки)")
print("INFO " + ("бот ждал сеть и был остановлен" if zavis else f"бот завершился с кодом {kod} (ключ ненастоящий, Telegram не принял)"))
print("TAIL " + " | ".join(l.replace(kusok, "***") for l in tekst.strip().splitlines()[-3:])[:300])
PYEOF
  while IFS= read -r line; do
    case "$line" in OK\ *) ok "${line#OK }" ;; FAIL\ *) bad "${line#FAIL }" ;; INFO\ *) echo "ℹ️  ${line#INFO }" ;; TAIL\ *) echo "    ${line#TAIL }" ;; *) echo "    $line" ;; esac
  done <"$T/run.out"
fi

echo "== 3. Библиотеки из маршрута «свой компьютер» ставятся"
SVOY="$T/svoy"; mkdir -p "$SVOY"
if venv "$SVOY"; then
  if pipi "openpyxl, pandas, python-docx, pdfplumber ставятся в среду проекта" openpyxl pandas python-docx pdfplumber; then
    ( cd "$SVOY" && "$VPY" -c 'import openpyxl, pandas, docx, pdfplumber' ) >"$T/imp.log" 2>&1 \
      && ok "все четыре библиотеки импортируются" || { bad "библиотеки не импортируются"; tail -5 "$T/imp.log" | sed 's/^/    /'; }
  fi
else bad "вторая среда .venv не создалась"; fi

echo "== 4. Обновить.bat по правилам Windows запускает Python проекта"
# Текст навыка — с сервера, общий с Mac (Обновить.command); как сделать .bat, говорит rules/WINDOWS.md
RULE=$(grep 'Обновить.bat' "$PKG/rules/WINDOWS.md")
for frag in '@echo off' 'cd /d "%~dp0"' '.venv\Scripts\python.exe' 'pause'; do
  grep -qF -- "$frag" <<<"$RULE" && ok "WINDOWS.md: для Обновить.bat есть «$frag»" || bad "WINDOWS.md: для Обновить.bat нет «$frag»"
done
case "$OSTYPE" in msys* | cygwin*) WIN=1 ;; *) WIN=0 ;; esac
if [ "$WIN" = 1 ]; then
  mkdir -p "$SVOY/vyhod"; printf 'print("obrabotka ok")\n' >"$SVOY/obrabotka.py"
  # .bat из частей правила, как его напишет Claude (с LF); проводник заменён на echo
  printf '%s\n' '@echo off' 'cd /d "%~dp0"' '.venv\Scripts\python.exe obrabotka.py || (pause & exit /b 1)' 'echo explorer vyhod' >"$SVOY/Обновить.bat"
  ( cd "$SVOY" && cmd.exe //c "Обновить.bat" ) >"$T/bat.log" 2>&1
  if grep -q 'obrabotka ok' "$T/bat.log" && grep -q 'explorer vyhod' "$T/bat.log"; then ok "Обновить.bat запускает .venv\\Scripts\\python.exe и потом открывает результат"
  else bad "Обновить.bat из навыка не отработал"; tail -6 "$T/bat.log" | sed 's/^/    /'; fi
else
  echo "ℹ️  .bat проверяется только на Windows"
fi

echo
if [ "$fail" -eq 0 ]; then echo "✅ Шаблон бота и библиотеки: всё в порядке ($n_ok проверок)"; else echo "❌ Шаблон бота и библиотеки: есть провалы"; fi
exit "$fail"
