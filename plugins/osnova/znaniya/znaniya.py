#!/usr/bin/env python3
"""Посыльный за знаниями метода: полный текст навыка — с сервера, по личному ключу человека.

  znaniya.py           инструмент для Claude (сервер MCP): poluchit_navyk
  znaniya.py proverit  проверить сохранённый ключ

Ключ лежит в ~/.config/korobeinikov-ai/klyuch, читать его может только этот пользователь Windows. Кладёт его личная
строка установки из бота метода, мимо разговора. Значение ключа не печатается никогда. Только стандартная библиотека.
Версия для Windows: запускается через hooks/py.sh (настоящий Python, не заглушка магазина) с -X utf8. Тексты на сервере
общие с Mac, поэтому команды Python и пути среды проекта в них переводятся на Windows (остальное — rules/WINDOWS.md).
"""
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

SERVER = "https://korobeinikov-ai.up.railway.app"
# Подмена адреса — только на этот же компьютер (для тестов): чужой проект не уведёт ключ на свой сервер своей настройкой.
ADRES = os.environ.get("KAI_ZNANIYA_URL", SERVER)
if not re.match(r"^http://127\.0\.0\.1:\d+$", ADRES):
    ADRES = SERVER
FAYL = Path(os.environ.get("KAI_KLYUCH") or Path.home() / ".config/korobeinikov-ai/klyuch")
KOREN = Path(__file__).resolve().parent.parent  # корень пакета
VID = re.compile(r"^kai_[A-Za-z0-9_-]{43}$")

KAK_POLUCHIT = (
    "Скажи человеку простыми словами: «Опыт автора в пакете открывается по личному доступу. Откройте бота метода "
    "в Telegram — https://t.me/korobeinikov_aibot — и нажмите «Хочу доступ». Когда автор откроет доступ, бот пришлёт "
    "личный текст для установки: вставьте его сюда, в Claude, и нажмите Enter. Метод уже стоит, поэтому текст только "
    "подключит доступ». Пришлёт — делай по инструкции из этого текста: ссылка в нём срабатывает один раз и сама кладёт "
    "ключ в закрытый файл, мимо разговора. Сам ключ в разговор не проси и файл ключа не открывай. Пока доступа нет, "
    "работай по своим знаниям и предупреди человека, что опыт автора сейчас недоступен."
)
NE_OTVETIL = (
    "Сервер знаний метода сейчас не ответил. Попробуй ещё раз через минуту. Не вышло — скажи человеку, что опыт "
    "автора временно недоступен, и работай дальше по своим знаниям, предупредив его."
)


def klyuch_s_diska():
    try:
        k = FAYL.read_text().strip()
    except FileNotFoundError:
        return None
    return k if VID.match(k) else None


def zapros(put, klyuch, parametry=None):
    """(код ответа, текст). Код 0 — сервер не ответил. Сбой сети и 5xx повторяем один раз."""
    adres = f"{ADRES}{put}" + (f"?{urlencode(parametry)}" if parametry else "")
    for popytka in (1, 2):
        try:
            with urlopen(Request(adres, headers={"Authorization": f"Bearer {klyuch}"}), timeout=20) as r:
                return r.status, r.read().decode("utf-8")
        except HTTPError as e:
            if e.code < 500 or popytka == 2:
                return e.code, e.read().decode("utf-8", "replace")
        except (URLError, OSError) as e:
            print(f"znaniya: сервер не ответил ({type(e).__name__})", file=sys.stderr)
            if popytka == 2:
                return 0, ""
        time.sleep(2)
    return 0, ""


def po_windows(tekst):
    """`python3 …` → настоящий Python через py.sh (python3 здесь часто заглушка магазина), `.venv/bin/…` → `.venv/Scripts/….exe`."""
    py = f'bash "{KOREN.as_posix()}/hooks/py.sh" '
    tekst = re.sub(r"\bpython3 (?=[\"'-]|[\w./${}-]+\.py\b)", lambda _m: py, tekst)
    return re.sub(r"\.venv/bin/(pip|python)3?\b", r".venv/Scripts/\1.exe", tekst)


def poluchit(imya):
    """(текст, это ошибка?) для Claude."""
    klyuch = klyuch_s_diska()
    if not klyuch:
        return "Ключа к методу KOROBEINIKOV AI на этом компьютере нет, полного текста навыка не будет. " + KAK_POLUCHIT, True
    kod, tekst = zapros("/navyk", klyuch, {"imya": imya})
    if kod == 200:
        papka = KOREN / "skills" / imya.split("/")[0]
        tekst = tekst.replace("${CLAUDE_SKILL_DIR}", papka.as_posix()).replace("${CLAUDE_PLUGIN_ROOT}", KOREN.as_posix())
        return po_windows(tekst), False
    if kod == 401:
        return "Сохранённый ключ к методу не подошёл. " + KAK_POLUCHIT, True
    if kod == 403:
        zakryt = (
            "Доступ к опыту автора по этому ключу закрыт. Скажи человеку: «Доступ к методу закрыт — напишите автору». "
            "Работай дальше по своим знаниям."
        )
        return zakryt, True
    if kod in (404, 429):
        return tekst, True
    return NE_OTVETIL, True


INSTRUMENT = {
    "name": "poluchit_navyk",
    "description": (
        "Полный текст навыка метода KOROBEINIKOV AI по его имени (например `baza` или `railway/POLOMKI.md`). "
        "Звать, когда заголовок навыка говорит, что полный текст — на сервере."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {"imya": {"type": "string", "description": "Имя навыка или его части, например baza"}},
        "required": ["imya"],
    },
}


def otvetit(nomer, rezultat=None, oshibka=None):
    soobshchenie = {"jsonrpc": "2.0", "id": nomer}
    soobshchenie["error" if oshibka else "result"] = oshibka or rezultat
    sys.stdout.write(json.dumps(soobshchenie, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def server():
    for stroka in sys.stdin:
        try:
            z = json.loads(stroka)
        except json.JSONDecodeError as e:
            print(f"znaniya: непонятный запрос: {e}", file=sys.stderr)
            continue
        metod, nomer = z.get("method"), z.get("id")
        if nomer is None:
            continue  # уведомление, ответа не ждут
        if metod == "initialize":
            otvetit(nomer, {
                "protocolVersion": (z.get("params") or {}).get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "znaniya", "version": "1"},
            })
        elif metod == "tools/list":
            otvetit(nomer, {"tools": [INSTRUMENT]})
        elif metod == "tools/call":
            imya = str(((z.get("params") or {}).get("arguments") or {}).get("imya", ""))
            try:
                tekst, oshibka = poluchit(imya)
            except (OSError, ValueError) as e:  # посыльный не падает: Claude получает понятный ответ, причина — в stderr
                print(f"znaniya: сбой: {e!r}", file=sys.stderr)
                tekst, oshibka = NE_OTVETIL, True
            otvetit(nomer, {"content": [{"type": "text", "text": tekst}], "isError": oshibka})
        elif metod == "ping":
            otvetit(nomer, {})
        else:
            otvetit(nomer, oshibka={"code": -32601, "message": f"нет метода {metod}"})


def proverit():
    klyuch = klyuch_s_diska()
    if not klyuch:
        print("❌ Ключа к методу на этом компьютере нет.")
        return 1
    kod, tekst = zapros("/kto", klyuch)
    if kod == 200:
        kto = json.loads(tekst)
        print(f"✅ Ключ работает: {kto['imya']}, код {kto['kod']}.")
        return 0
    print({401: "❌ Ключ не подошёл: нажмите в боте метода «Новая строка установки» и вставьте присланный текст в Claude.",
           403: "❌ Доступ по этому ключу закрыт автором."}.get(kod, "⚠️ Сервер знаний не ответил, ключ сохранён — проверю позже."))
    return 1


if __name__ == "__main__":
    deystvie = sys.argv[1] if len(sys.argv) > 1 else ""
    if deystvie == "proverit":
        sys.exit(proverit())
    server()
