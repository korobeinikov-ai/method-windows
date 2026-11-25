"""Склад метода на этой машине — для проверки на настоящей Windows (CI) без настоящего сервера.

  python -I tests/sklad.py ПАПКА_РЕПО СЕРТИФИКАТ.crt КЛЮЧ.key [ЖУРНАЛ]

Собирает склад из этой папки так, как его кладёт выпуск мастерской: каталог .claude-plugin/marketplace.json, где каждый
пакет plugins/* — zip-архив с источником archive и sha256 на https://metod.korobeinikov.ai/windows/plugins/…, рядом
инструкция, установщик и страница. Отдаёт по HTTPS на порту 443 теми же адресами и заголовками, что сервер метода.
Домен сюда ведёт запись в hosts (её делает проверка), сертификат проверка делает доверенным. Ещё отдаёт
/windows/plohoy.json — тот же каталог с неверной sha256: Claude Code должен отказаться ставить из него.
Принимает отчёт об установке, как сервер метода (POST /u/<ссылка>/otchet): поля формы — строкой «OTCHET: {json}» в журнал
(по ней проверка сверяет отчёт), ответ 200; ссылка начинается с «sboy» — ответ 503 (проверка: сбой отправки установку не
ломает). Остальные адреса — 404. Журнал запросов — в stderr или дописывается в файл ЖУРНАЛ: по нему видно, что Claude Code
брал архивы отсюда.
"""
import hashlib
import http.server
import io
import json
import re
import ssl
import sys
import urllib.parse
import zipfile
from pathlib import Path

DOMEN = "https://metod.korobeinikov.ai"
TEKSTY = {"/windows": "README.md", "/windows/": "README.md", "/windows/CLAUDE.md": "CLAUDE.md",
          "/windows/install.ps1": "install.ps1"}


def arhiv(paket):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as z:
        for f in sorted(paket.rglob("*")):
            if f.is_file() and "__pycache__" not in f.parts:
                z.write(f, f.relative_to(paket).as_posix())
    return buf.getvalue()


def sobrat(repo):
    """Адрес → (тип, тело): всё, что отдаёт Windows-склад сервера метода."""
    katalog = json.loads((repo / ".claude-plugin/marketplace.json").read_text(encoding="utf-8"))
    otvety = {}
    for p in katalog["plugins"]:
        telo = arhiv(repo / p["source"])
        sha = hashlib.sha256(telo).hexdigest()
        put = f"/windows/plugins/{p['name']}-{sha[:12]}.zip"
        otvety[put] = ("application/zip", telo)
        p["source"] = {"source": "archive", "url": DOMEN + put, "sha256": sha}
    otvety["/windows/marketplace.json"] = ("application/json", json.dumps(katalog, ensure_ascii=False).encode())
    plohoy = {**katalog, "name": "proverka-plohoy-sha",
              "plugins": [{**p, "source": {**p["source"], "sha256": "0" * 64}} for p in katalog["plugins"]]}
    otvety["/windows/plohoy.json"] = ("application/json", json.dumps(plohoy, ensure_ascii=False).encode())
    for put, f in TEKSTY.items():
        otvety[put] = ("text/plain; charset=utf-8", (repo / f).read_bytes())
    return otvety


def main(repo, cert, key, zhurnal=None):
    if zhurnal:  # запуск без окна (проверка зовёт его мимо своего шага): журнал — в файл, построчно
        sys.stdout = sys.stderr = open(zhurnal, "a", buffering=1, encoding="utf-8")  # noqa: SIM115 — открыт до конца
    otvety = sobrat(Path(repo))

    class H(http.server.BaseHTTPRequestHandler):
        def otvet(self, telo=True):
            tip, dannye = otvety.get(self.path.split("?")[0], ("text/plain; charset=utf-8", None))
            self.send_response(200 if dannye is not None else 404)
            dannye = dannye if dannye is not None else "Такого на складе нет.".encode()
            self.send_header("Content-Type", tip)
            self.send_header("Content-Length", str(len(dannye)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            if telo:
                self.wfile.write(dannye)

        def do_GET(self):
            self.otvet()

        def do_HEAD(self):
            self.otvet(telo=False)

        def do_POST(self):
            m = re.fullmatch(r"/u/([A-Za-z0-9_-]+)/otchet", self.path)
            telo = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode("utf-8", "replace")
            kod = 404 if not m else 503 if m[1].startswith("sboy") else 200
            if kod == 200:
                pola = {k: v[0] for k, v in urllib.parse.parse_qs(telo, keep_blank_values=True).items()}
                print("OTCHET: " + json.dumps({**pola, "_put": self.path}), flush=True)
            self.send_response(kod)
            self.send_header("Content-Length", "0")
            self.end_headers()

    s = http.server.ThreadingHTTPServer(("0.0.0.0", 443), H)
    c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    c.load_cert_chain(cert, key)
    s.socket = c.wrap_socket(s.socket, server_side=True)
    print("SKLAD: " + ", ".join(sorted(otvety)), flush=True)
    s.serve_forever()


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    main(*sys.argv[1:])
