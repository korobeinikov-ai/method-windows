#!/usr/bin/env bash
# Посыльный за знаниями (znaniya/znaniya.py) с подставным сервером на этом же компьютере: тот же запуск, что в .mcp.json
# (py.sh -I -X utf8), русские буквы целы, команды Mac в тексте переведены на Windows, ключ не печатается.
# Запуск: bash tests/test-znaniya.sh (Git Bash на Windows или Mac). Печатает ✅/❌, при провале код 1.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$REPO/plugins/osnova"
PY=(bash "$PKG/hooks/py.sh")
fail=0
ok()  { echo "✅ $1"; }
bad() { echo "❌ $1"; fail=1; }

T=$(mktemp -d)
SERVER_PID=""
trap '[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$T"' EXIT
KLYUCH="kai_$(printf 'Q%.0s' $(seq 43))"  # подставной, собирается при запуске
printf '%s\n' "$KLYUCH" > "$T/klyuch"

cat > "$T/server.py" <<'EOF'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
klyuch, port_fayl = sys.argv[1], sys.argv[2]
TEKST = ('# Railway\n\nПривет ✅\n`python3 "${CLAUDE_SKILL_DIR}/klyuch.py" vzyat TOKEN`\n'
         '`.venv/bin/pip install -r requirements.txt` и `.venv/bin/python -m unittest`\n')
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        svoy = self.headers.get("Authorization") == f"Bearer {klyuch}"
        telo = (TEKST if svoy else "Ключ не подошёл.").encode("utf-8")
        self.send_response(200 if svoy else 401)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(telo)
    def log_message(self, *a):
        pass
s = HTTPServer(("127.0.0.1", 0), H)
open(port_fayl, "w").write(str(s.server_address[1]))
s.serve_forever()
EOF
"${PY[@]}" "$T/server.py" "$KLYUCH" "$T/port" </dev/null >/dev/null 2>&1 &
SERVER_PID=$!
disown "$SERVER_PID" 2>/dev/null || true
for _ in $(seq 50); do [ -s "$T/port" ] && break; sleep 0.1; done
PORT=$(tr -d '\r' < "$T/port" 2>/dev/null)
[ -n "$PORT" ] || { bad "подставной сервер не запустился"; exit 1; }

zapros() {  # MCP по stdin, как его зовёт Claude Code: initialize, список, вызов
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"poluchit_navyk","arguments":{"imya":"railway"}}}' |
    KAI_ZNANIYA_URL="http://127.0.0.1:$PORT" KAI_KLYUCH="$1" "${PY[@]}" -I -X utf8 "$PKG/znaniya/znaniya.py" 2>"$T/err"
}

out=$(zapros "$T/klyuch"); code=$?
[ $code -eq 0 ] && echo "$out" | grep -q '"poluchit_navyk"' && ok "посыльный отвечает Claude по MCP" || { bad "посыльный не ответил (код $code)"; cat "$T/err"; }
echo "$out" | grep -q 'Привет ✅' && ok "русские буквы и значки целы" || bad "русские буквы сломались"
echo "$out" | grep -q 'hooks/py.sh\\" \\"[^"]*/skills/railway/klyuch.py' && ok "python3 в тексте → настоящий Python через py.sh, путь навыка подставлен" \
  || { bad "python3 не переведён"; echo "$out" | tail -1 | cut -c1-400; }
echo "$out" | grep -q '\.venv/Scripts/pip\.exe install' && echo "$out" | grep -q '\.venv/Scripts/python\.exe -m' \
  && ok ".venv/bin → .venv/Scripts/….exe" || bad ".venv/bin не переведён"
echo "$out" | grep -q 'python3 \\"' && bad "в тексте остался python3" || ok "python3 в командах не осталось"
echo "$out" | grep -qE '[A-Za-z]:\\\\' && bad "путь пришёл с обратными слешами" || ok "пути — с прямыми слешами"
grep -qF "$KLYUCH" <<<"$out$(cat "$T/err")" && bad "ключ попал в вывод" || ok "ключ не печатается"

out=$(zapros "$T/net-klyucha")
echo "$out" | grep -q 'korobeinikov_aibot' && echo "$out" | grep -q '"isError": true' \
  && ok "нет ключа — Claude отправляет человека в бота метода" || bad "без ключа нет подсказки про бота"

echo
if [ "$fail" -eq 0 ]; then echo "✅ Посыльный: всё в порядке"; else echo "❌ Посыльный: есть провалы"; fi
exit "$fail"
