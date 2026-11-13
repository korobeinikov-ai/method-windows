#!/bin/bash
# SessionStart: правила пакета + состояние человека — в каждый сеанс (старт, /clear, сжатие).
# Работает в Git Bash на Windows. Сам Python не нужен: он только проверяется. Обычный текст на выходе
# Claude видит как контекст (CLAUDE.md из плагина Claude Code не грузит). Предел — 10 000 знаков на весь вывод.
# Порядок вывода: сначала состояние человека (тревоги, первый запуск), потом правила. Предел обрезает хвост,
# и обрезаться должен хвост правил, а не «Первый запуск» или тревога о неработающей охране.
# Состояние — в постоянной папке пакета ($CLAUDE_PLUGIN_DATA), её не стирают обновления:
#   gotovo — проводник пройден; nastroyki-versiya — какие настройки человек принял или отклонил;
#   sprosit-zadachu — проект только что заведён: один раз спросить «что хотите сделать?»;
#   zadacha — задача, которую человек назвал ещё до настройки: напомнить вместо вопроса.
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DATA="${CLAUDE_PLUGIN_DATA:-}"
TPL="$ROOT/skills/start/nastroyki.json"
rd() { [ -f "$1" ] && tr -d '\r' < "$1"; } # файлы состояния с Windows могут быть с \r\n

# --- состояние человека: тревоги, первый запуск, напоминания
dynamic() {
# Охрана держится на Git Bash и Python. Нет их — ключи никто не стережёт.
missing=""
command -v git >/dev/null 2>&1 || missing="Git"
bash "$ROOT/hooks/py.sh" -c '' </dev/null >/dev/null 2>&1 || missing="${missing:+$missing, }Python"
if [ -n "$missing" ]; then
  cat <<EOF

## ⚠️ Охрана пакета сейчас НЕ работает
Не найдено: $missing. Без них ключи и пароли никто не стережёт. До любой другой работы скажи человеку простыми
словами, что установка не закончилась, и почини: запусти подготовку сам, в фоне (до 15 минут) —
\`powershell.exe -NoProfile -Command '\$env:METHOD_NO_LAUNCH=1; irm https://raw.githubusercontent.com/korobeinikov-ai/method-windows/main/install.ps1 | iex'\` —
потом пусть человек полностью закроет Claude (и значок у часов внизу справа: правой кнопкой → выход) и открыть снова: новые программы Claude увидит только так.
EOF
fi

# Настройки, которые ставит установка. Их нет — охрана или русский текст работают хуже.
warn=""
[ "${PYTHONUTF8:-}" = 1 ] || warn="$warn
- Не включён PYTHONUTF8: русские буквы в скриптах могут ломаться."
[ "${CLAUDE_CODE_USE_POWERSHELL_TOOL:-}" = 0 ] || warn="$warn
- Включён инструмент PowerShell (CLAUDE_CODE_USE_POWERSHELL_TOOL не 0): через него команды идут мимо основной охраны."
if [ -n "$warn" ]; then
  cat <<EOF

## ⚠️ Настройки Windows не закончены
$warn
Почини сам: в фоне \`powershell.exe -NoProfile -Command '\$env:METHOD_NO_LAUNCH=1; irm https://raw.githubusercontent.com/korobeinikov-ai/method-windows/main/install.ps1 | iex'\`, потом скажи человеку одной строкой:
полностью закрыть Claude (и значок у часов внизу справа: правой кнопкой → выход) и открыть снова.
EOF
fi

if [ -z "$DATA" ]; then
  echo "KOROBEINIKOV AI: нет постоянной папки пакета (CLAUDE_PLUGIN_DATA) — первый запуск не отслеживаю" >&2
  return 0
fi

# Строка внизу окна (настройка statusLine) смотрит в постоянную папку: кладём свежую копию каждый сеанс
mkdir -p "$DATA" && cp "$ROOT/skills/start/stroka.py" "$DATA/stroka.py" \
  || echo "KOROBEINIKOV AI: не обновил строку внизу окна ($DATA/stroka.py)" >&2

if [ ! -f "$DATA/gotovo" ]; then
  cat <<'EOF'

## Первый запуск KOROBEINIKOV AI
Человек ещё не прошёл проводник. На первое же его сообщение (даже «привет») запусти навык `start` и веди
по нему. Если он сразу написал задачу — скажи, что сначала за пару минут всё настроишь как у автора,
а потом сразу к ней; задачу запомни.
EOF
  return 0
fi

have=$(rd "$DATA/nastroyki-versiya" || echo 0)
have=${have:-0}
new=$(sed -n 's/.*"versiya": *\([0-9][0-9]*\).*/\1/p' "$TPL" | head -1 | tr -d '\r')
if [ -n "$new" ] && [ "$have" -lt "$new" ] 2>/dev/null; then
  what=$(sed -n 's/.*"chto_novogo": *"\([^"]*\)".*/\1/p' "$TPL" | head -1 | tr -d '\r')
  cat <<EOF

## Автор обновил настройки
У человека настройки версии $have, в пакете — $new: $what. В естественной паузе, не перебивая задачу,
одной строкой предложи обновить. Согласится — навык \`start\`, только настройки из шага 2.
EOF
fi

if [ -f "$DATA/sprosit-zadachu" ]; then
  proj=$(rd "$DATA/sprosit-zadachu")
  there=$(cd "$proj" 2>/dev/null && pwd -P)
  here=$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && pwd -P)
  if [ -n "$there" ] && [ "$here" = "$there" ]; then  # метку тратит только сеанс в папке проекта
    task=$(rd "$DATA/zadacha")  # уже укорочена при записи (novyi_proekt.py)
    rm -f "$DATA/sprosit-zadachu" "$DATA/zadacha"
    if [ -n "$task" ]; then
      ask="Ещё до настройки человек назвал задачу: «${task}». Напомни её одной строкой и предложи начать
с неё — заново не спрашивай"
    else
      ask="Спроси «Что хотите сделать?»"
    fi
    cat <<EOF

## Проект только что заведён
Проводник пройден, это папка нового проекта. На первое сообщение коротко поздравь. $ask
(навык \`start\`, шаг «За дело»).
EOF
  elif [ -n "$there" ]; then
    cat <<EOF

## Новый проект ждёт
Недавно заведён проект в $proj, но Claude открыт в другой папке. Хочет человек работать над
проектом — в приложении открой новый сеанс в этой папке, в терминале: \`/exit\`, затем \`cd $proj; claude\`.
EOF
  fi
fi
}

dynamic

# --- правила пакета и подсказки для Windows
cat "$ROOT/rules/PRAVILA.md" || echo "KOROBEINIKOV AI: не прочитал правила пакета ($ROOT/rules/PRAVILA.md)" >&2
if [ -f "$ROOT/rules/WINDOWS.md" ]; then
  cat "$ROOT/rules/WINDOWS.md" || echo "KOROBEINIKOV AI: не прочитал подсказки для Windows ($ROOT/rules/WINDOWS.md)" >&2
fi
# последняя строка блока подсказок: чем запускать Python (python3 на Windows часто ведёт в заглушку магазина)
echo "- Команда Python здесь: \`bash \"${ROOT//\\//}/hooks/py.sh\"\`"
