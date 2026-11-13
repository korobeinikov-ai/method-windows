#!/usr/bin/env bash
# Тексты навыков, правил, судьи и скелета: говорят про Windows, а не про Mac; ссылки на файлы живые.
# Запуск: bash tests/test-teksty.sh (Git Bash на Windows или Mac). Печатает ✅/❌, при провале код 1.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$REPO/plugins/osnova"
fail=0; n_ok=0
ok()  { echo "✅ $1"; n_ok=$((n_ok + 1)); }
bad() { echo "❌ $1"; fail=1; }

# Файлы, о которых тексты: навыки (кроме проводника), правила, судья, скелет, описание пакета
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
  cd "$PKG" && find skills/railway skills/telegram-bot skills/avtoru skills/baza skills/premortem skills/svoy-kompyuter \
    skills/systematic-debugging rules agents skelet .claude-plugin -type f \
    \( -name '*.md' -o -name '*.json' -o -name '*.py' -o -name '*.txt' -o -name '.python-version' \) | sort)
cd "$PKG" || exit 1
echo "Проверяем файлов: ${#FILES[@]}"

# scan <описание> <шаблон> [исключить-файл]: в тексте не должно быть совпадений (строки-шебанги не считаем)
scan() {
  local what=$1 pat=$2 skip=${3:-NONE} hits
  hits=$(grep -n -E -- "$pat" "${FILES[@]}" 2>/dev/null | grep -v -E ":[0-9]+:#!" | grep -v -E "^$skip:" | head -5)
  if [ -n "$hits" ]; then bad "$what"; printf '%s\n' "$hits" | cut -c1-160 | sed 's/^/    /'; else ok "$what"; fi
}
scan "нет слов про Mac и его инструменты" '\bMac\b|macOS|mac_ver|Homebrew|\bbrew\b|xcode-select|pbpaste|pbcopy|osascript|\.command|open -a|/opt/homebrew|⌘' 'rules/WINDOWS.md'
scan "нет python3 в командах (на Windows это часто пустышка)" 'python3' 'rules/WINDOWS.md'
scan "нет .venv/bin и Cmd" '\.venv/bin|Cmd\b' 'rules/WINDOWS.md'
scan "нет голой команды open и chmod" '(`|^|[ (])open [a-z"$]|chmod ' 'rules/WINDOWS.md'
scan "нет абсолютных путей чужого компьютера" '/Users/[A-Za-z]|C:\\Users\\[A-Za-z]'
scan "нет ссылок на полку и витрину Mac" 'korobeinikov-ai-method|korobeinikov-ai/method([^-]|$)'

# Запуск Python из навыков: через py.sh пакета, который лежит на месте
USES=$(grep -l 'hooks/py.sh' "${FILES[@]}" 2>/dev/null | head -20)
if [ -n "$USES" ]; then
  if [ -f hooks/py.sh ]; then ok "навыки запускают Python через hooks/py.sh, и он на месте"; else bad "навыки зовут hooks/py.sh, а его нет"; fi
fi
bad_py=$(grep -h -o -E 'hooks/py\.sh".{0,3}' "${FILES[@]}" 2>/dev/null | grep -v -E '^hooks/py\.sh" ("|-m)' | head -3)
[ -z "$bad_py" ] && ok "после py.sh везде идёт скрипт или -m" || { bad "после py.sh непонятная команда"; printf '%s\n' "$bad_py" | sed 's/^/    /'; }

# Описания: у каждого навыка и судьи есть name и description, plugin.json читается и без Mac
for f in skills/*/SKILL.md agents/*.md; do
  head -5 "$f" | grep -q '^name: ' && head -5 "$f" | grep -q '^description: ' || bad "нет name/description в начале $f"
done
ok "у всех навыков и судьи есть name и description"
# Python — только через py.sh: голая команда python3 на Windows часто ведёт в заглушку магазина
[ -f hooks/py.sh ] && PYX=(bash hooks/py.sh) || PYX=()
if [ ${#PYX[@]} -gt 0 ] && "${PYX[@]}" -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); sys.exit(0 if d["name"]=="osnova" and "Windows" in d["description"] else 1)' .claude-plugin/plugin.json </dev/null; then
  ok "plugin.json читается: имя osnova, в описании Windows"
else
  bad "plugin.json: нет имени osnova или слова Windows в описании"
fi

# Правила: подсказки для Windows на месте и короткие (всё вместе выводится в каждый сеанс, предел 10 000 знаков)
[ -f rules/WINDOWS.md ] && ok "rules/WINDOWS.md на месте" || bad "нет rules/WINDOWS.md"
n=$("${PYX[@]}" -c 'import sys; print(sum(len(open(f, encoding="utf-8").read()) for f in sys.argv[1:]))' rules/PRAVILA.md rules/WINDOWS.md </dev/null | tr -d '\r')
[ "$n" -le 9000 ] && ok "правила и подсказки для Windows: $n знаков (до 9000, в сеанс влезает с запасом)" || bad "правила и подсказки слишком длинные: $n знаков"
grep -q 'Windows 10/11' rules/PRAVILA.md && ok "в правилах стек — Windows 10/11" || bad "в правилах не указан Windows 10/11"

echo
if [ "$fail" -eq 0 ]; then echo "✅ Тексты: всё в порядке ($n_ok проверок)"; else echo "❌ Тексты: есть провалы"; fi
exit "$fail"
