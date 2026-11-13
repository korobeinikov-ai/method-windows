#!/usr/bin/env python3
"""Telegram из разговора с Claude. Ключ берётся из .env проекта и не печатается никогда.

  telegram.py proverit                  живой ли ключ и как зовут бота
  telegram.py kto КОД                   кто прислал боту этот код: имя и номер
  telegram.py svoi [--dobavit N] [--ubrat N]  список своих людей, первый — владелец
  telegram.py otpravit ФАЙЛ [--podpis]  отправить файл владельцу (до 50 МБ)
"""
import argparse
import json
import mimetypes
import re
import sys
import uuid
from http.client import HTTPException
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "railway"))
from klyuch import nayti, stop, zapisat

API = "https://api.telegram.org"  # адрес не настраивается: ключ бота уходит только сюда
PREDEL_FAYLA = 50 * 1024 * 1024
ZAKRYTYE_PAPKI = {".ssh", ".aws", "secrets"}


def api(metod, dannye=None, zagolovki=None):
    """Запрос к Telegram. Адрес с ключом не печатаем: в ошибках только текст от Telegram."""
    klyuch = nayti("TELEGRAM_BOT_TOKEN")
    if not klyuch:
        stop("Ключа бота ещё нет: сначала шаг с BotFather")
    zapros = Request(f"{API}/bot{klyuch}/{metod}", data=dannye, headers=zagolovki or {})
    try:
        try:
            with urlopen(zapros, timeout=300) as r:
                otvet = json.load(r)
        except HTTPError as e:
            otvet = json.load(e)
    except ValueError:
        stop("Telegram ответил непонятно: похоже на сбой у него, попробуй через минуту")
    except (OSError, HTTPException):
        stop("Нет связи с Telegram: проверь интернет и попробуй ещё раз")
    if otvet.get("ok"):
        return otvet["result"]
    kod, opisanie = otvet.get("error_code"), otvet.get("description", "без описания")
    if kod == 401:
        stop("Telegram не принял ключ: возьми новый у BotFather")
    if kod == 409:
        stop("Бот уже работает на Railway: человек узнает свой номер, написав боту")
    stop(f"Telegram ответил: {opisanie}")


def proverit():
    bot = api("getMe")
    print(f"✅ Ключ живой, бот @{bot['username']} ({bot['first_name']})")


def kto(kod):
    """Только тот, кто прислал код. Имя задаёт сам человек: это подпись, поэтому лишние знаки убираем."""
    lyudi = {}
    for obnovlenie in api("getUpdates"):
        soobshchenie = obnovlenie.get("message", {})
        if soobshchenie.get("text", "").strip() == kod:
            avtor = soobshchenie["from"]
            lyudi[avtor["id"]] = re.sub(r"[^\w -]", "", avtor.get("first_name", "без имени"))[:32]
    if not lyudi:
        stop("Этого кода боту ещё не присылали: попроси человека отправить его ещё раз")
    for nomer, imya in lyudi.items():
        print(f"{imya}: {nomer}")


def svoi(dobavit, ubrat):
    spisok = [n.strip() for n in (nayti("TELEGRAM_SVOI") or "").split(",") if n.strip()]
    if dobavit is not None and str(dobavit) not in spisok:
        spisok.append(str(dobavit))
    if ubrat is not None:
        if spisok and spisok[0] == str(ubrat):
            stop("Это владелец бота: его не убираю")
        spisok = [n for n in spisok if n != str(ubrat)]
    if dobavit is not None or ubrat is not None:
        zapisat("TELEGRAM_SVOI", ",".join(spisok))
    print(f"Свои люди: {', '.join(spisok) or 'пока никого'}")


def otpravit(put, podpis):
    fayl = Path(put)
    if not fayl.is_file():
        stop(f"Нет такого файла: {put}")
    chasti = {chast.casefold() for chast in fayl.resolve().parts}  # на Windows .ENV — тот же файл, что .env
    if fayl.resolve().name.casefold().startswith(".env") or ZAKRYTYE_PAPKI & chasti:
        stop("Файлы с ключами в Telegram не отправляю")
    if fayl.stat().st_size > PREDEL_FAYLA:
        stop("Файл больше 50 МБ: Telegram такой от бота не примет")
    spisok = nayti("TELEGRAM_SVOI")
    if not spisok:
        stop("Не знаю номер владельца: сначала шаг, где он пишет боту")
    granica = uuid.uuid4().hex
    polya = {"chat_id": spisok.split(",")[0].strip()}
    if podpis:
        polya["caption"] = podpis
    telo = b"".join(
        f'--{granica}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode() for k, v in polya.items()
    )
    tip = mimetypes.guess_type(fayl.name)[0] or "application/octet-stream"
    imya = fayl.name.replace('"', "'").replace("\r", "").replace("\n", "")
    telo += (
        f'--{granica}\r\nContent-Disposition: form-data; name="document"; filename="{imya}"\r\n'
        f"Content-Type: {tip}\r\n\r\n"
    ).encode()
    try:
        soderzhimoe = fayl.read_bytes()
    except OSError:
        stop("Не могу прочитать файл: он открыт в другой программе или закрыт для чтения. Закрой его и повтори")
    telo += soderzhimoe + f"\r\n--{granica}--\r\n".encode()
    api("sendDocument", telo, {"Content-Type": f"multipart/form-data; boundary={granica}"})
    print(f"✅ Файл {fayl.name} отправлен в Telegram")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("deystvie", choices=["proverit", "kto", "svoi", "otpravit"])
    p.add_argument("chto", nargs="?", help="файл или код")
    p.add_argument("--dobavit", type=int)
    p.add_argument("--ubrat", type=int)
    p.add_argument("--podpis")
    a = p.parse_args()
    if a.deystvie == "proverit":
        proverit()
    elif a.deystvie == "kto":
        if not a.chto:
            stop("Назови код, который человек прислал боту")
        kto(a.chto)
    elif a.deystvie == "svoi":
        svoi(a.dobavit, a.ubrat)
    else:
        if not a.chto:
            stop("Назови файл")
        otpravit(a.chto, a.podpis)


if __name__ == "__main__":
    main()
