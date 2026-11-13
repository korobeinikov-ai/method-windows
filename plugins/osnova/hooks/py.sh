#!/bin/bash
# Запуск Python для хуков и скриптов пакета: bash py.sh <скрипт.py> [аргументы].
# На Windows команда python3 часто ведёт в заглушку магазина Microsoft: она ничего не запускает,
# и охрана молча не работала бы. Поэтому настоящий Python ищем запуском: пробуем каждую найденную
# программу (python, python3, py -3 — все копии на пути поиска, не только первую) и берём ту,
# что правда выполнила код.
# Не нашли Python — не молчим. Хуку с git-командой не даём пройти (ключи без охраны нельзя
# сохранять и отправлять), остальным вызовам только говорим об этом в stderr.
export PYTHONUTF8=1 # иначе русский текст и значки ломаются на кодировке Windows
# Windows ищет программу по голому имени сначала в текущей папке, а хуки запускаются в папке проекта:
# чужой git.exe оттуда не должен запускаться. С этой переменной в окружении процесса Windows папку не смотрит.
export NoDefaultCurrentDirectoryInExePath=1

# настоящий Python: выполнил код и вернул 42, а не напечатал совет «поставьте из магазина»
try() { [ "$("$@" -c 'print(6 * 7)' </dev/null 2>/dev/null)" = 42 ]; }

# путь Windows (C:\...) -> путь Git Bash (/c/...), где есть cygpath
unixpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; else printf '%s' "$1"; fi; }

PY=()
find_python() {
  local name p base
  for name in python python3 py; do
    while IFS= read -r p; do
      if [ "$name" = py ]; then
        try "$p" -3 && PY=("$p" -3) && return 0
      else
        try "$p" && PY=("$p") && return 0
      fi
    done < <(type -ap "$name" 2>/dev/null)
  done
  # Python только что поставили, а этот сеанс путь к нему ещё не знает
  for base in "${LOCALAPPDATA:-}" "${PROGRAMFILES:-}"; do
    [ -n "$base" ] || continue
    for p in "$(unixpath "$base")"/Programs/Python/Python3*/python.exe "$(unixpath "$base")"/Python3*/python.exe; do
      [ -f "$p" ] && try "$p" && PY=("$p") && return 0
    done
  done
  return 1
}

if find_python; then exec "${PY[@]}" "$@"; fi

# Python не найден. У хука на входе JSON с событием и командой — читаем его без Python.
input=""
case "${1:-}" in */hooks/*.py) IFS= read -r -t 3 -d '' input ;; esac
shopt -s nocasematch # Windows не различает регистр: Git.exe add — та же команда
re_pre='"hook_event_name"[[:space:]]*:[[:space:]]*"PreToolUse"'
re_git='git[^|;&]*(add|commit|push)'
# (только встроенные команды bash: пути поиска сейчас могут быть пустыми)
if [[ $input =~ $re_pre ]] && [[ $input =~ $re_git ]]; then
  printf '%s\n' \
    "ЗАБЛОКИРОВАНО: на этом компьютере не найден Python, охрана ключей не работает, а без неё" \
    "сохранять и отправлять в git нельзя. Скажи человеку простыми словами: установка не закончилась." \
    "Запусти подготовку ещё раз сам, в фоне: powershell.exe -NoProfile -Command '\$env:METHOD_NO_LAUNCH=1; irm https://raw.githubusercontent.com/korobeinikov-ai/method-windows/main/install.ps1 | iex'" \
    "Потом человеку: полностью закрыть Claude (и значок у часов внизу справа: правой кнопкой → выход) и открыть снова. Охрану не обходи." >&2
  exit 2
fi
printf '%s\n' \
  "KOROBEINIKOV AI: не нашёл Python — охрана ключей сейчас не работает. Попросите Claude ещё раз" \
  "поставить метод, потом полностью закрыть Claude (и значок у часов внизу справа: правой кнопкой → выход) и открыть снова." >&2
exit 1
