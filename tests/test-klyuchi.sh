#!/usr/bin/env bash
# Тесты передачи ключей: буфер обмена -> .env -> Railway; Telegram; заметки автору.
# Главное, что проверяем: значение ключа не печатается нигде и лежит только в .env, а .env закрыт от других.
# Запуск: Git Bash на Windows (главная мерка) или Mac (быстрая проверка логики с подменой буфера): bash tests/test-klyuchi.sh
# Печатает ✅/❌ по шагам, при провале выходит с кодом 1. Ключ-подделка собирается из кусков во время запуска.
# Проверка «значения нет в выводе» идёт поиском куска ключа; найденный вывод не показываем.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$REPO/plugins/osnova"
KLYUCH="$PKG/skills/railway/klyuch.py"
TELEGRAM="$PKG/skills/telegram-bot/telegram.py"
AVTORU="$PKG/skills/avtoru/otpravit.py"
fail=0; n_ok=0
ok()  { echo "✅ $1"; n_ok=$((n_ok + 1)); }
bad() { echo "❌ $1"; fail=1; }
note() { echo "ℹ️  $1"; }

case "$OSTYPE" in msys* | cygwin*) WIN=1 ;; *) WIN=0 ;; esac
wpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -aw "$1"; else printf '%s' "$1"; fi; }

# Python — так же, как зовут его навыки: через py.sh пакета
if [ -f "$PKG/hooks/py.sh" ]; then PY=(bash "$PKG/hooks/py.sh"); else PY=(python3); fi
newpy() { "$@" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' </dev/null 2>/dev/null; }
if ! newpy "${PY[@]}"; then   # на Mac системный Python старый: берём любой новее
  for c in python3.14 python3.13 python3.12 python3.11 python3.10; do command -v "$c" >/dev/null && newpy "$c" && PY=("$c") && break; done
fi
newpy "${PY[@]}" || { echo "❌ Нужен Python 3.10 или новее: ${PY[*]}"; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
: >"$T/all.out"

# Ключ-подделка в виде ключа Telegram: куски собираются здесь, готовой строки в файлах нет
export PYTHONDONTWRITEBYTECODE=1
KEY="$RANDOM$RANDOM$RANDOM:fake$(printf '%s' key)-$(date +%s)-$RANDOM-$RANDOM"
FRAG="${KEY#*:}"; FRAG="${FRAG:4:18}"
export TEST_KEY="$KEY" TEST_FRAG="$FRAG"

has()  { grep -qF -- "$1" "$T/last.out"; }
# runpy <папка> <скрипт> <аргументы...>: код в RC, вывод в last.out и all.out (ставим PYTHONUTF8=1 как установка)
runpy() { local cwd=$1; shift; ( cd "$cwd" && "${PY[@]}" "$@" ) >"$T/last.out" 2>&1; RC=$?; cat "$T/last.out" >>"$T/all.out"; }
show() { if grep -qF -- "$FRAG" "$T/last.out"; then echo "    (вывод скрыт: в нём кусок ключа)"; else sed 's/^/    /' "$T/last.out" | head -12; fi; }
# expect <код> <описание> [текст в выводе]
expect() {
  local want=$1 what=$2 text=${3:-}
  if [ "$RC" -ne "$want" ]; then bad "$what (код $RC, ждали $want)"; show
  elif [ -n "$text" ] && ! has "$text"; then bad "$what (нет текста «${text}» в выводе)"; show
  else ok "$what"; fi
}
mkproj() { mkdir -p "$1"; git init -q "$1"; printf '.env\n' >"$1/.gitignore"; }
env_has() { # env_has <проект> <строка>: точная строка в .env, значение не печатаем
  ENVFILE="$(wpath "$1/.env")" LINE="$2" "${PY[@]}" -c 'import os,sys; sys.exit(0 if os.environ["LINE"] in open(os.environ["ENVFILE"], encoding="utf-8").read().splitlines() else 1)' </dev/null
}
# acl_only_me <файл>: у .env права только у текущего пользователя (Windows)
acl_only_me() {
  local out who
  out=$(icacls "$(wpath "$1")" 2>&1 | tr -d '\r')
  who=$("$(cygpath -u "${SYSTEMROOT:-C:\\Windows}")/System32/whoami.exe" | tr -d '\r')
  [ "$(printf '%s\n' "$out" | grep -c ':(')" -eq 1 ] || return 1
  printf '%s\n' "$out" | grep -qiF -- "$who" || return 1
  ! printf '%s\n' "$out" | grep -qiE 'Everyone|BUILTIN|NT AUTHORITY|Authenticated Users'
}

echo "== 1. Скрипты ключей собираются"
if "${PY[@]}" -c 'import sys
for f in sys.argv[1:]:
    compile(open(f, encoding="utf-8").read(), f, "exec")' "$(wpath "$KLYUCH")" "$(wpath "$TELEGRAM")" "$(wpath "$AVTORU")" </dev/null; then ok "klyuch.py, telegram.py, otpravit.py без синтаксических ошибок"
else bad "синтаксическая ошибка в скриптах ключей"; fi

echo "== 2. Логика с подменой буфера обмена (на любой системе)"
KLYUCH_DIR="$(wpath "$(dirname "$KLYUCH")")" TEST_TMP="$(wpath "$T")" "${PY[@]}" - >"$T/b.out" 2>&1 <<'PYEOF'
import contextlib, io, json, os, subprocess, sys
from pathlib import Path

sys.path.insert(0, os.environ["KLYUCH_DIR"])
import klyuch

KEY, FRAG, TMP = os.environ["TEST_KEY"], os.environ["TEST_FRAG"], Path(os.environ["TEST_TMP"])
# git не должен брать правила игнорирования из настроек этого компьютера
os.environ.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", XDG_CONFIG_HOME=str(TMP / "xdg"))
res = []


def check(name, cond):
    res.append(("OK " if cond else "FAIL ") + name)


def vyzov(f, *a):
    """Выполняет функцию, возвращает (код, всё напечатанное)."""
    buf, kod = io.StringIO(), 0
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        try:
            f(*a)
        except SystemExit as e:
            kod = e.code if isinstance(e.code, int) else 1
    return kod, buf.getvalue()


def proekt(imya, zakryt=True):
    p = TMP / imya
    p.mkdir()
    subprocess.run(["git", "init", "-q", str(p)], check=True)
    if zakryt:
        (p / ".gitignore").write_text(".env\n", encoding="utf-8")
    os.chdir(p)
    return p


# Буфер обмена подменяем; настоящие права и история буфера — только на Windows
BUF = {"v": KEY, "ochishchen": False}
klyuch.chitat_bufer = lambda: BUF["v"]


def ochistit():
    BUF["v"], BUF["ochishchen"] = "", True
    return True


klyuch.ochistit_bufer = ochistit
if sys.platform != "win32":
    klyuch.zakryt_fayl = lambda f: None
    klyuch.istoriya_bufera_vklyuchena = lambda: False

# --- vzyat
p = proekt("p1")
kod, vyvod = vyzov(klyuch.vzyat, "TEST_KEY")
check("ключ из буфера попал в .env точной строкой, без BOM и \\r", (p / ".env").read_bytes() == f"TEST_KEY={KEY}\n".encode())
check("после ключа буфер очищен", BUF["ochishchen"] and BUF["v"] == "")
check("vzyat сказал ✅ и не напечатал ключ", kod == 0 and "✅" in vyvod and FRAG not in vyvod)

pered = (p / ".env").read_bytes()
BUF["v"] = "два слова, это не ключ"
kod, vyvod = vyzov(klyuch.vzyat, "TEST_KEY2")
check("текст с пробелами из буфера не принимается и .env не меняется", kod == 1 and "не ключ" in vyvod and (p / ".env").read_bytes() == pered)
BUF["v"] = "коротко"
kod, vyvod = vyzov(klyuch.vzyat, "TEST_KEY2")
check("короткий текст из буфера не принимается", kod == 1 and (p / ".env").read_bytes() == pered)
BUF["v"] = ""
kod, vyvod = vyzov(klyuch.vzyat, "TEST_KEY2")
check("пустой буфер не принимается", kod == 1 and (p / ".env").read_bytes() == pered)
BUF["v"] = "\ufeff" + KEY + "b\r\n"
kod, vyvod = vyzov(klyuch.vzyat, "TEST_KEY3")
check("BOM и перевод строки вокруг ключа в буфере отбрасываются", kod == 0 and klyuch.nayti("TEST_KEY3") == KEY + "b")

# --- Railway: подменяем запуск программы, смотрим, что ей отдают
nastoyashchiy_run, nastoyashchiy_nayti = subprocess.run, klyuch.nayti_programmu
vyzovy, otvet = [], {"rc": 0, "out": "", "err": ""}


def podmena_run(argv, **kw):
    if "railway" not in os.path.basename(str(argv[0])).lower():
        return nastoyashchiy_run(argv, **kw)
    vyzovy.append((argv, kw))
    return subprocess.CompletedProcess(argv, otvet["rc"], otvet["out"], otvet["err"])


klyuch.subprocess.run = podmena_run
klyuch.nayti_programmu = lambda imya: "railway.exe" if imya == "railway" else nastoyashchiy_nayti(imya)

os.chdir(p)
kod, vyvod = vyzov(klyuch.peredat, "TEST_KEY", "bot", True)
argv, kw = vyzovy[-1]
check("ключ уходит в Railway через стандартный ввод", kw.get("input") == KEY and "--stdin" in argv)
check("ключа нет ни в одном аргументе команды Railway", all(FRAG not in str(a) for a in argv))
check("peredat сказал ✅ и не напечатал ключ", kod == 0 and "✅" in vyvod and FRAG not in vyvod)

otvet.update(rc=1, err=f"сбой, ключ {KEY}", out="")
kod, vyvod = vyzov(klyuch.peredat, "TEST_KEY", "bot", True)
check("ошибка Railway не показывает ключ", kod == 1 and FRAG not in vyvod and "***" in vyvod)

otvet.update(rc=0, out=f"строка журнала {KEY}", err="")
kod, vyvod = vyzov(klyuch.zhurnal, "bot")
check("журнал со значением ключа: тревога, самого значения в ответе нет", kod == 1 and FRAG not in vyvod)
otvet.update(rc=0, out="чистый журнал", err="")
kod, vyvod = vyzov(klyuch.zhurnal, "bot")
check("чистый журнал проходит проверку", kod == 0 and "✅" in vyvod and FRAG not in vyvod)

otvet.update(rc=0, out=json.dumps({"MY_NAME": KEY, "RAILWAY_X": "1"}), err="")
kod, vyvod = vyzov(klyuch.imena, "bot")
check("imena печатает только имена настроек", kod == 0 and "MY_NAME" in vyvod and "RAILWAY_X" not in vyvod and FRAG not in vyvod)
config = {"services": {"bot": {"source": {"rootDirectory": "bot", "repo": "a/b", "branch": "main"},
                               "deploy": {"restartPolicyType": "ALWAYS"}, "variables": {"SECRET": {"value": KEY}}}}}
otvet.update(rc=0, out=json.dumps(config), err="")
kod, vyvod = vyzov(klyuch.nastroyki)
check("nastroyki печатает устройство частей без значений ключей", kod == 0 and "rootDirectory" in vyvod and FRAG not in vyvod)
klyuch.subprocess.run, klyuch.nayti_programmu = nastoyashchiy_run, nastoyashchiy_nayti

# --- .env: перепись не портит чужие строки, концы строк и кодировка
p4 = proekt("p4")
(p4 / ".env").write_bytes("\ufeff# Комментарий по-русски\r\nOTHER=value\r\n".encode("utf-8"))
klyuch.zapisat("TEST_KEY4", KEY)
tekst = (p4 / ".env").read_bytes()
check("после записи в .env нет BOM и \\r", not tekst.startswith(b"\xef\xbb\xbf") and b"\r" not in tekst)
check("чужие строки и русский комментарий в .env сохранены", "# Комментарий по-русски\nOTHER=value\n".encode() in tekst)
check("значение читается обратно", klyuch.nayti("TEST_KEY4") == KEY and klyuch.nayti("OTHER") == "value")
klyuch.zapisat("TEST_KEY4", KEY + "z")
check("повторная запись заменяет строку, а не дописывает", (p4 / ".env").read_text(encoding="utf-8").count("TEST_KEY4=") == 1)

# --- без .gitignore ключ не берём
p2 = proekt("p2", zakryt=False)
BUF["v"] = KEY
kod, vyvod = vyzov(klyuch.vzyat, "TEST_KEY")
check(".env не закрыт от git: ключ не берётся и файл не создаётся", kod == 1 and not (p2 / ".env").exists() and FRAG not in vyvod)

# --- программы ищем по PATH, а не в текущей папке проекта; не нашли — не запускаем голое имя
p5 = proekt("p5")
exe = klyuch.SUFFIKS
(p5 / ("railway" + exe)).write_bytes(b"")
(p5 / ("git" + exe)).write_bytes(b"")  # подмена git в папке проекта: Windows запустила бы её по голому имени
staryi = os.environ["PATH"]
os.environ["PATH"] = str(TMP / "net-takoy-papki")
check("railway из папки проекта не подхватывается", klyuch.nayti_programmu("railway") is None)
(TMP / "bin").mkdir()
(TMP / "bin" / ("railway" + exe)).write_bytes(b"")
os.environ["PATH"] = str(TMP / "bin")
check("railway из PATH находится по полному пути", klyuch.nayti_programmu("railway") == str(TMP / "bin" / ("railway" + exe)))
os.environ["PATH"] = os.pathsep.join(["", ".", "bin", str(TMP / "net-takoy-papki")])  # пустое и относительное в PATH
check("пустые и относительные записи PATH игнорируются", klyuch.nayti_programmu("railway") is None)
os.environ.pop("ProgramFiles", None); os.environ.pop("ProgramW6432", None)
os.environ["PATH"] = str(TMP / "net-takoy-papki")
os.chdir(p5)
if klyuch.nayti_programmu("git") is None:  # (если у человека git лежит в ~/.local/bin, этот случай не воспроизвести)
    kod, vyvod = vyzov(klyuch.koren)
    check("git не нашёлся: klyuch.py говорит об этом, а не запускает git из папки проекта", kod == 1 and "Нет программы Git" in vyvod)
else:
    check("git найден не в папке проекта", not klyuch.nayti_programmu("git").startswith(str(p5)))
os.environ["PATH"] = staryi

print("\n".join(res))
PYEOF
RC=$?
cat "$T/b.out" >>"$T/all.out"
sed "s/$FRAG/***/g" "$T/b.out" | grep -v -E '^(OK|FAIL) ' | sed 's/^/    /' | head -20
if [ $RC -ne 0 ]; then bad "проверка логики упала до конца (код $RC)"; fi
while IFS= read -r line; do
  case "$line" in OK\ *) ok "${line#OK }" ;; FAIL\ *) bad "${line#FAIL }" ;; esac
done <"$T/b.out"

echo "== 3. Скрипты запускаются так, как их зовут навыки"
PROJ="$T/проект"; mkproj "$PROJ"; mkdir "$PROJ/подпапка"
runpy "$PROJ" "$(wpath "$KLYUCH")"
expect 2 "klyuch.py без аргументов: подсказка вместо падения"
# вывод со значками не ломается и в «русской» кодировке консоли
( cd "$PROJ" && PYTHONUTF8=0 PYTHONIOENCODING=cp1251 "${PY[@]}" "$(wpath "$KLYUCH")" imena ) >"$T/last.out" 2>&1; RC=$?; cat "$T/last.out" >>"$T/all.out"
expect 1 "значки ❌ и русский текст выводятся и при кодировке консоли cp1251" "❌ Назови часть на Railway"
if [ "$WIN" = 1 ] && [ -f "$PKG/hooks/py.sh" ]; then
  SKILL_W="$(wpath "$PKG/skills/railway")"   # так приходит ${CLAUDE_SKILL_DIR}: с обратными чертами
  ( cd "$PROJ" && eval "bash \"$SKILL_W/../../hooks/py.sh\" \"$SKILL_W/klyuch.py\" imena" ) >"$T/last.out" 2>&1; RC=$?; cat "$T/last.out" >>"$T/all.out"
  expect 1 "команда из навыка (путь с \\ и ../../hooks/py.sh) запускает скрипт" "Назови часть на Railway"
fi
if [ "$WIN" = 0 ]; then
  runpy "$PROJ" "$KLYUCH" vzyat TEST_KEY
  expect 1 "на системе без буфера Windows vzyat честно отказывает" "только на Windows"
fi

echo "== 4. Настоящий буфер обмена и права на файл (Windows)"
CLIP=none
set_clip() { CLIPVAL="$1" powershell.exe -NoProfile -NonInteractive -Command 'if ($env:CLIPVAL) { Set-Clipboard -Value $env:CLIPVAL } else { Set-Clipboard -Value $null }' >/dev/null 2>&1; }
clip_length() { powershell.exe -NoProfile -NonInteractive -Command '$c = Get-Clipboard -Raw; if ($c) { $c.Trim().Length } else { 0 }' 2>/dev/null | tr -d '\r\n '; }
if [ "$WIN" = 1 ]; then
  PROBE="probe-$$-$RANDOM-0123456789"
  if set_clip "$PROBE" && [ "$(KDIR="$(wpath "$(dirname "$KLYUCH")")" "${PY[@]}" -c 'import os,sys; sys.path.insert(0, os.environ["KDIR"]); import klyuch; print(klyuch.chitat_bufer())' </dev/null 2>/dev/null | tr -d '\r\n')" = "$PROBE" ]; then
    CLIP=real
  fi
fi
if [ "$CLIP" = real ]; then
  set_clip "$KEY"
  runpy "$PROJ/подпапка" "$(wpath "$KLYUCH")" vzyat TEST_KEY
  expect 0 "настоящий буфер: ключ взят (папка проекта с русским именем, запуск из подпапки)" "✅"
  has "$FRAG" && bad "vzyat напечатал кусок ключа" || ok "vzyat не напечатал ключ"
  has "Не удалось закрыть" && bad "vzyat не смог закрыть .env от других и сказал об этом" || ok "vzyat закрыл .env без предупреждений"
  env_has "$PROJ" "TEST_KEY=$KEY" && ok "ключ лёг в .env проекта (а не в подпапку)" || bad "ключа нет в .env проекта"
  [ "$(clip_length)" = 0 ] && ok "буфер обмена Windows очищен" || bad "в буфере обмена что-то осталось"
  acl_only_me "$PROJ/.env" && ok ".env закрыт от других: права только у текущего пользователя" || { bad ".env открыт не только текущему пользователю"; icacls "$(wpath "$PROJ/.env")" 2>&1 | sed "s/$FRAG/***/g" | head -8; }
  runpy "$PROJ" "$(wpath "$KLYUCH")" vzyat TEST_KEY
  expect 1 "пустой буфер после очистки: «не ключ»" "не ключ"
  set_clip "два слова, а не ключ"
  runpy "$PROJ" "$(wpath "$KLYUCH")" vzyat TEST_KEY
  expect 1 "настоящий буфер: текст с пробелами не принимается" "не ключ"
else
  note "настоящий буфер обмена на этом компьютере не проверен (нет Windows или буфер недоступен): проверена только логика с подменой буфера"
fi

echo "== 5. Telegram: ключ не печатается"
P3="$T/bot"; mkproj "$P3"
runpy "$P3" "$(wpath "$TELEGRAM")" proverit
expect 1 "без ключа бота telegram.py отказывает понятно" "Ключа бота ещё нет"
printf 'TELEGRAM_BOT_TOKEN=%s\n' "$KEY" >"$P3/.env"
DEAD=http://127.0.0.1:9    # закрытый порт: проверка пути «нет связи» без интернета
offline() { ( cd "$P3" && HTTPS_PROXY=$DEAD https_proxy=$DEAD HTTP_PROXY=$DEAD http_proxy=$DEAD NO_PROXY= no_proxy= "${PY[@]}" "$@" ) >"$T/last.out" 2>&1; RC=$?; cat "$T/last.out" >>"$T/all.out"; }
offline "$(wpath "$TELEGRAM")" proverit
expect 1 "нет связи с Telegram: понятное сообщение, ключа в нём нет" "Нет связи с Telegram"
runpy "$P3" "$(wpath "$TELEGRAM")" proverit
if [ "$RC" -eq 1 ] && { has "Telegram не принял ключ" || has "Telegram ответил:" || has "Нет связи с Telegram"; }; then ok "настоящий запрос с чужим ключом: отказ без падения (отказ Telegram или нет сети)"
else bad "настоящий запрос с чужим ключом: непонятный ответ (код $RC)"; show; fi
if [ "$WIN" = 1 ]; then   # запись в .env закрывает файл правами Windows: на Mac этот шаг не запускается
  runpy "$P3" "$(wpath "$TELEGRAM")" svoi --dobavit 111222
  expect 0 "telegram.py svoi --dobavit записывает номер" "Свои люди: 111222"
  env_has "$P3" "TELEGRAM_SVOI=111222" && env_has "$P3" "TELEGRAM_BOT_TOKEN=$KEY" && ok "в .env обе строки на месте" || bad "в .env потерялась строка"
  acl_only_me "$P3/.env" && ok ".env после записи снова закрыт от других" || bad ".env после записи открыт не только текущему пользователю"
else
  printf 'TELEGRAM_SVOI=111222\n' >>"$P3/.env"
fi
runpy "$P3" "$(wpath "$TELEGRAM")" svoi --ubrat 111222
expect 1 "владельца бота убрать нельзя" "владелец"
runpy "$P3" "$(wpath "$TELEGRAM")" otpravit .env
expect 1 "файл .env в Telegram не отправляется" "Файлы с ключами"
runpy "$P3" "$(wpath "$TELEGRAM")" otpravit "$(wpath "$P3/.env")"
expect 1 "то же по полному пути" "Файлы с ключами"
mkdir "$P3/.ssh"; printf 'x' >"$P3/.ssh/id"
runpy "$P3" "$(wpath "$TELEGRAM")" otpravit .ssh/id
expect 1 "файлы из .ssh в Telegram не отправляются" "Файлы с ключами"
printf 'PK-проба' >"$P3/отчёт за неделю.xlsx"
offline "$(wpath "$TELEGRAM")" otpravit "отчёт за неделю.xlsx" --podpis "Итоги: проверка ✅"
expect 1 "файл с русским именем собирается и уходит в сеть (связи нет — сказано честно)" "Нет связи с Telegram"
offline "$(wpath "$TELEGRAM")" kto 123456
expect 1 "telegram.py kto доходит до сети" "Нет связи с Telegram"

echo "== 6. Заметка автору (otpravit.py): русский текст, домашняя папка, без GitHub"
TH="$T/home"; mkdir -p "$TH"
avtoru() { ( cd "$PROJ" && HOME="$TH" USERPROFILE="$(wpath "$TH")" GH_CONFIG_DIR="$T/gh" GH_TOKEN= GITHUB_TOKEN= GH_ENTERPRISE_TOKEN= "${PY[@]}" "$(wpath "$AVTORU")" "$@" ) >"$T/last.out" 2>&1; RC=$?; cat "$T/last.out" >>"$T/all.out"; }
avtoru </dev/null
expect 2 "без аргументов: «Нужно: --gde …», ничего не ушло" "Нужно:"
printf 'Проверка: русский текст и значок ✅ в папке %s\n' "$(wpath "$TH")" >"$T/zametka.in"
avtoru --gde "навык «railway», шаг 3" --tip затык <"$T/zametka.in"
expect 1 "без входа в GitHub заметка не уходит, причина названа" "Не ушло"
ZAMETKI="$TH/vibecoding/zametki-dlya-avtora.md"
if [ -f "$ZAMETKI" ]; then
  ZAMETKI_W="$(wpath "$ZAMETKI")" "${PY[@]}" -c '
import os, sys
t = open(os.environ["ZAMETKI_W"], encoding="utf-8").read()
sys.exit(0 if "Проверка: русский текст и значок ✅" in t else 1)' </dev/null && ok "заметка сохранена в UTF-8: русские буквы и значок целы" || bad "заметка сохранена с испорченной кодировкой"
  grep -qF -- "$(wpath "$TH")" "$ZAMETKI" && bad "домашняя папка в заметке не заменена на ~" || ok "домашняя папка в заметке заменена на ~"
else bad "заметка не сохранилась в zametki-dlya-avtora.md"; fi
SYS=$(HOME="$TH" USERPROFILE="$(wpath "$TH")" AVTORU_DIR="$(wpath "$(dirname "$AVTORU")")" "${PY[@]}" -c '
import os, sys
sys.path.insert(0, os.environ["AVTORU_DIR"])
import otpravit
print(otpravit.footer())' </dev/null 2>&1 | tr -d '\r' | head -1)
case "$SYS" in
  *"пакет "*" · "*"Claude Code "*) ok "подпись заметки собирается: «$(printf '%s' "$SYS" | sed 's/Claude Code .*/Claude Code …/')»" ;;
  *) bad "подпись заметки не собралась" ;;
esac
[ "$WIN" = 1 ] && { case "$SYS" in *Windows*) ok "в подписи заметки Windows, а не macOS" ;; *) bad "в подписи заметки нет слова Windows" ;; esac; }

echo "== 7. Итог: ключа нет ни в одном выводе и нигде, кроме .env"
if grep -qF -- "$FRAG" "$T/all.out"; then bad "кусок ключа найден в выводе скриптов"; else ok "в выводе всех скриптов куска ключа нет ($(wc -l <"$T/all.out" | tr -d ' ') строк проверено)"; fi
LEAK=$(grep -rlF --exclude=.env -- "$FRAG" "$PROJ" "$P3" 2>/dev/null | head -3)
if [ -n "$LEAK" ]; then bad "ключ найден в файлах проекта, кроме .env"; else ok "кроме .env, ключа нет ни в одном файле проектов (включая .git)"; fi

echo
if [ "$fail" -eq 0 ]; then echo "✅ Ключи: всё в порядке ($n_ok проверок)"; else echo "❌ Ключи: есть провалы"; fi
exit "$fail"
