#!/usr/bin/env python3
"""Ключи мимо чата: буфер обмена → .env проекта → Railway. Значение ключа не печатается никогда.

  klyuch.py vzyat ИМЯ                                взять из буфера обмена и сохранить в .env
  klyuch.py peredat ИМЯ --service S [--bez-vykladki] передать из .env на Railway
  klyuch.py imena --service S                        какие настройки есть на Railway (только имена)
  klyuch.py nastroyki                                как устроены части на Railway (без значений ключей)
  klyuch.py zhurnal --service S                      нет ли значений ключей в журналах новой выкладки
"""
import argparse
import ctypes
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

for potok in (sys.stdout, sys.stderr):
    if hasattr(potok, "reconfigure"):  # Windows без этого ломает русские буквы и значки в выводе
        potok.reconfigure(encoding="utf-8", errors="replace")

SISTEMNAYA = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
SUFFIKS = ".exe" if os.name == "nt" else ""
os.environ["NoDefaultCurrentDirectoryInExePath"] = "1"  # Windows не ищет программы в текущей папке (там может лежать подмена)


def stop(tekst):
    print(f"❌ {tekst}")
    sys.exit(1)


def nayti_programmu(imya):
    """Полный путь к программе: ~/.local/bin, папки из PATH (только полные пути) и обычное место Git.
    Текущую папку не смотрим: Windows ищет голое имя сначала в ней, а в чужом проекте там может лежать подмена.
    Не нашли — None: голое имя не запускаем."""
    papki = [Path.home() / ".local" / "bin",
             *(Path(p) for p in os.environ.get("PATH", "").split(os.pathsep) if p and Path(p).is_absolute()),
             *(Path(os.environ[v]) / "Git" / "cmd" for v in ("ProgramFiles", "ProgramW6432") if os.environ.get(v))]
    return next((str(p / f"{imya}{SUFFIKS}") for p in papki if (p / f"{imya}{SUFFIKS}").is_file()), None)


def git(argumenty, **kw):
    programma = nayti_programmu("git")
    if not programma:
        stop("Нет программы Git: пусть человек ещё раз вставит строку установки из инструкции метода")
    return subprocess.run([programma, *argumenty], check=False, **kw)


def koren():
    r = git(["rev-parse", "--show-toplevel"], capture_output=True, text=True, encoding="utf-8")
    return Path(r.stdout.strip()) if r.returncode == 0 else Path.cwd()


def stroki_env():
    fayl = koren() / ".env"
    return fayl.read_text(encoding="utf-8-sig").splitlines() if fayl.exists() else []


def nayti(imya):
    """Значение из .env проекта или None."""
    for stroka in stroki_env():
        if stroka.startswith(f"{imya}="):
            return stroka.split("=", 1)[1]
    return None


def prochitat(imya):
    znachenie = nayti(imya)
    if znachenie is None:
        stop(f"В файле ключей проекта нет {imya}")
    return znachenie


# Кроме владельца файл не должен читать никто: система, администраторы, все пользователи, вошедшие, «все»
POSTORONNIE = ("S-1-5-18", "S-1-5-32-544", "S-1-5-32-545", "S-1-5-11", "S-1-1-0")


def zakryt_fayl(fayl):
    """Права на файл — только у текущего пользователя Windows. Не получилось закрыть — говорим, а не молчим."""
    r = subprocess.run([str(SISTEMNAYA / "whoami.exe"), "/user", "/fo", "csv", "/nh"],
                       capture_output=True, text=True, errors="replace", check=False)
    sid = r.stdout.strip().split(",")[-1].strip('"')
    zakryt = False
    if r.returncode == 0 and re.fullmatch(r"S-1-[\d-]+", sid):
        icacls = str(SISTEMNAYA / "icacls.exe")
        # сначала права владельцу и отмена унаследованных, потом убираем явно выданные чужим: файл ни на миг не закрыт для хозяина
        shagi = (["/inheritance:r", "/grant:r", f"*{sid}:(F)"], ["/remove:g", *(f"*{s}" for s in POSTORONNIE if s != sid)])
        zakryt = all(subprocess.run([icacls, str(fayl), *shag], capture_output=True, text=True, errors="replace",
                                    check=False).returncode == 0 for shag in shagi)
    if not zakryt:
        print(f"⚠️ Не удалось закрыть {fayl.name} от других пользователей компьютера. Ключ в нём всё равно "
              "не попадёт в git, но скажи об этом человеку", file=sys.stderr)


def zapisat(imya, znachenie):
    """Заменяет строку ключа или дописывает её. Файл читает только владелец компьютера."""
    fayl = koren() / ".env"
    stroki = stroki_env()
    novaya = f"{imya}={znachenie}"
    if any(s.startswith(f"{imya}=") for s in stroki):
        stroki = [novaya if s.startswith(f"{imya}=") else s for s in stroki]
    else:
        stroki.append(novaya)
    # Файл закрываем до записи ключа: ключ ни на миг не лежит на диске с открытым доступом.
    fayl.touch()
    zakryt_fayl(fayl)
    fayl.write_text("\n".join(stroki) + "\n", encoding="utf-8", newline="\n")


def okna():
    """Системные вызовы Windows для буфера обмена: без PowerShell, ключ не попадает ни в чьи аргументы."""
    from ctypes import wintypes

    user32, kernel32 = ctypes.WinDLL("user32", use_last_error=True), ctypes.WinDLL("kernel32", use_last_error=True)
    user32.OpenClipboard.argtypes, user32.OpenClipboard.restype = [wintypes.HWND], wintypes.BOOL
    user32.GetClipboardData.argtypes, user32.GetClipboardData.restype = [wintypes.UINT], wintypes.HANDLE
    user32.EmptyClipboard.restype = wintypes.BOOL
    user32.CloseClipboard.restype = wintypes.BOOL
    kernel32.GlobalLock.argtypes, kernel32.GlobalLock.restype = [wintypes.HGLOBAL], wintypes.LPVOID
    kernel32.GlobalUnlock.argtypes, kernel32.GlobalUnlock.restype = [wintypes.HGLOBAL], wintypes.BOOL
    return user32, kernel32


def otkryt_bufer(user32):
    for _ in range(20):  # другая программа может держать буфер долю секунды
        if user32.OpenClipboard(None):
            return
        time.sleep(0.1)
    stop("Буфер обмена занят другой программой: закрой её и попробуй ещё раз")


def chitat_bufer():
    """Текст из буфера обмена (юникод, как его положила программа) или пустая строка."""
    user32, kernel32 = okna()
    otkryt_bufer(user32)
    try:
        ruchka = user32.GetClipboardData(13)  # 13 — обычный текст
        adres = kernel32.GlobalLock(ruchka) if ruchka else None
        if not adres:
            return ""
        try:
            return ctypes.wstring_at(adres)
        finally:
            kernel32.GlobalUnlock(ruchka)
    finally:
        user32.CloseClipboard()


def ochistit_bufer():
    user32, _ = okna()
    otkryt_bufer(user32)
    try:
        return bool(user32.EmptyClipboard())
    finally:
        user32.CloseClipboard()


def istoriya_bufera_vklyuchena():
    """В истории буфера (Win+V) ключ остаётся, даже когда сам буфер очищен."""
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Clipboard") as kluch:
            return winreg.QueryValueEx(kluch, "EnableClipboardHistory")[0] == 1
    except OSError:  # настройки нет — Windows считает историю выключенной
        return False


def vzyat(imya):
    r = git(["check-ignore", "-q", ".env"], cwd=koren(), capture_output=True)
    if r.returncode != 0:
        stop("Файл ключей не закрыт от git: сначала добавь .env в .gitignore")
    znachenie = chitat_bufer().strip("\ufeff \t\r\n")
    if len(znachenie) < 20 or re.search(r"\s", znachenie):
        stop("В буфере обмена не ключ. Попроси человека скопировать ключ ещё раз, целиком")
    zapisat(imya, znachenie)
    if ochistit_bufer():
        print(f"✅ {imya} сохранён в файле ключей проекта, буфер обмена очищен")
    else:
        print(f"✅ {imya} сохранён в файле ключей проекта\n"
              "⚠️ Буфер обмена очистить не удалось: пусть человек скопирует любое слово, чтобы ключ не остался в нём")
    if istoriya_bufera_vklyuchena():
        print("⚠️ Включена история буфера обмена: ключ остался в ней. Передай человеку: нажать Win+V и «Очистить всё»")


def vse_klyuchi():
    """Длинные значения из .env: короткие настройки вроде часового пояса ключами не считаем."""
    pary = (s.split("=", 1) for s in stroki_env() if "=" in s)
    return {imya: znachenie for imya, znachenie in pary if len(znachenie) >= 20}


def railway(argumenty, vvod=None, skryt=()):
    """Запускает программу Railway из корня проекта: связь с Railway запомнена по папке.

    Значения ключей не должны попасть в вывод даже при ошибке.
    """
    programma = nayti_programmu("railway")
    if not programma:
        stop("Нет программы Railway: сначала шаг 1 навыка railway")
    r = subprocess.run(
        [programma, *argumenty], input=vvod, capture_output=True, text=True, encoding="utf-8", errors="replace",
        check=False, cwd=koren(),
    )
    if r.returncode != 0:
        tekst = (r.stderr or r.stdout).strip()
        for znachenie in skryt:
            tekst = tekst.replace(znachenie, "***")
        stop(f"Railway не выполнил команду: {tekst}")
    return r.stdout


def peredat(imya, servis, bez_vykladki):
    znachenie = prochitat(imya)
    argumenty = ["variable", "set", imya, "--stdin", "--service", servis]
    if bez_vykladki:
        argumenty.append("--skip-deploys")
    railway(argumenty, vvod=znachenie, skryt=[znachenie])
    print(f"✅ {imya} передан на Railway: {servis}" + ("" if bez_vykladki else ", началась новая выкладка"))


def imena(servis):
    dannye = json.loads(railway(["variable", "list", "--service", servis, "--json"]))
    svoi = sorted(k for k in dannye if not k.startswith("RAILWAY_"))
    print("\n".join(svoi) if svoi else "Настроек пока нет")


def nastroyki():
    """Railway отдаёт настройки вместе со значениями ключей, поэтому берём только эти поля."""
    dannye = json.loads(railway(["environment", "config", "--json"]))
    polya = (("source", "rootDirectory"), ("source", "repo"), ("source", "branch"), ("deploy", "restartPolicyType"))
    chasti = {
        imya: {f"{gruppa}.{pole}": (chast.get(gruppa) or {}).get(pole) for gruppa, pole in polya}
        for imya, chast in dannye.get("services", {}).items()
    }
    print(json.dumps(chasti, ensure_ascii=False, indent=2))


def zhurnal(servis):
    """Запускать до показа журнала в разговоре: без --latest Railway смотрит прошлую удачную выкладку."""
    klyuchi = vse_klyuchi()
    if not klyuchi:
        stop("В файле ключей проекта нет ключей")
    for vid in ([], ["--build"]):
        vyvod = railway(["logs", *vid, "--latest", "--service", servis, "--lines", "500"], skryt=klyuchi.values())
        for imya, znachenie in klyuchi.items():
            if znachenie in vyvod:
                stop(f"Значение {imya} есть в журнале: ключ раскрыт, журнал не показывай, замени ключ и почини вывод")
    print(f"✅ В последних 500 строках журналов работы и сборки нет значений: {', '.join(klyuchi)}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("deystvie", choices=["vzyat", "peredat", "imena", "nastroyki", "zhurnal"])
    p.add_argument("imya", nargs="?")
    p.add_argument("--service")
    p.add_argument("--bez-vykladki", action="store_true")
    a = p.parse_args()
    if a.deystvie in ("vzyat", "peredat") and not a.imya:
        stop("Назови ключ: например, TELEGRAM_BOT_TOKEN")
    if a.deystvie not in ("vzyat", "nastroyki") and not a.service:
        stop("Назови часть на Railway: --service bot")
    if a.deystvie == "vzyat" and sys.platform != "win32":
        stop("Нет буфера обмена: этот шаг работает только на Windows")
    if a.deystvie == "vzyat":
        vzyat(a.imya)
    elif a.deystvie == "peredat":
        peredat(a.imya, a.service, a.bez_vykladki)
    elif a.deystvie == "imena":
        imena(a.service)
    elif a.deystvie == "nastroyki":
        nastroyki()
    else:
        zhurnal(a.service)


if __name__ == "__main__":
    main()
