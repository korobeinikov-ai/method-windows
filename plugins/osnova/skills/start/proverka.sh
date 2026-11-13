#!/bin/bash
# Проверка компьютера для KOROBEINIKOV AI (Windows, Git Bash): что есть, чего нет и как поставить.
# Ничего не меняет. Последняя строка — живая проверка: охрана секретов пакета действительно срабатывает.
HERE="$(cd "$(dirname "${0//\\//}")" && pwd)" # Claude Code может передать путь с обратными слешами
HOOKS="$(cd "$HERE/../../hooks" && pwd)"
TOOLS="bash $HERE/instrumenty.sh"
PATH="$HOME/.local/bin:$PATH"
INSTALL="запусти подготовку сам, в фоне, до 15 минут (что уже стоит — не тронет): powershell.exe -NoProfile -Command '\$env:METHOD_NO_LAUNCH=1; irm https://raw.githubusercontent.com/korobeinikov-ai/method-windows/main/install.ps1 | iex'; потом руки человека: полностью закрыть Claude (и значок у часов внизу справа: правой кнопкой → выход) и открыть снова"
bad=0
ok() { echo "✅ $1"; }
no() { echo "❌ $1 → $2"; bad=1; }
warn() { echo "⚠️ $1 → $2"; }

if command -v git >/dev/null; then ok "Git (в нём идут все команды)"
else no "Нет Git" "$INSTALL"; fi

# Заглушка магазина Microsoft тоже называется python, поэтому проверяем запуском, а не наличием
if bash "$HOOKS/py.sh" -c '' </dev/null >/dev/null 2>&1; then ok "Python"
else no "Нет настоящего Python (команда python из магазина Microsoft не считается)" "$INSTALL"; fi

# Охрана видит только команды Git Bash; без этой настройки Claude может пойти через PowerShell мимо неё
if [ "${CLAUDE_CODE_USE_POWERSHELL_TOOL:-}" = 0 ]; then ok "Команды идут через охрану"
else no "Команды могут идти мимо охраны через PowerShell" "$INSTALL"; fi

if [ -n "${CLAUDE_CODE_GIT_BASH_PATH:-}" ]; then
  if [ -f "$CLAUDE_CODE_GIT_BASH_PATH" ]; then ok "Git Bash найден"
  else no "Claude ищет Git Bash не там, где он лежит" "$INSTALL"; fi
else warn "Путь к Git Bash не записан: опыт автора с сервера может не открыться" "$INSTALL"; fi

if [ "${PYTHONUTF8:-}" = 1 ]; then ok "Русские буквы (UTF-8) включены"
else warn "Русские буквы в программах могут ломаться" "$INSTALL"; fi

if command -v gh >/dev/null; then
  ok "GitHub CLI (связь с GitHub)"
  if gh auth status >/dev/null 2>&1; then ok "Вход в GitHub"
  else warn "Нет входа в GitHub (начать не мешает)" "когда понадобится копия проекта: запусти в фоне gh auth login --web --git-protocol https, открой человеку https://github.com/login/device и покажи код; руки человека: вставить код, нажать «Authorize»; потом gh auth setup-git"; fi
else no "Нет GitHub CLI" "$TOOLS"; fi

if command -v gitleaks >/dev/null; then ok "Сканер секретов gitleaks"
else no "Нет сканера секретов gitleaks" "$TOOLS"; fi

# Живая проверка охраны: попытка добавить .env в git должна быть остановлена хуком пакета.
T=$(mktemp -d)
git -C "$T" init -q 2>/dev/null; echo "KEY=1" > "$T/.env"
WP=$(cd "$T" && { pwd -W 2>/dev/null || pwd; }) # путь с буквой диска: так его понимает Python на Windows
printf '{"tool_input":{"command":"git add .env"},"cwd":"%s"}' "$WP" | (cd "$T" && bash "$HOOKS/py.sh" "$HOOKS/block-env-commit.py") >/dev/null 2>&1
code=$?
rm -rf "$T"
if [ "$code" -eq 2 ]; then ok "Охрана секретов срабатывает"
else no "Охрана секретов НЕ сработала (код $code)" "сначала почини строки выше; не помогло — сообщи автору пакета"; fi

exit $bad
