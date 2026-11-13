#!/usr/bin/env python3
"""Строка внизу окна Claude Code: папка │ модель · глубина │ заполнение разговора │ лимит подписки.

Все цифры даёт сам Claude Code (JSON на входе), ничего не угадываем. Лимит подписки он присылает
только на подписке Pro/Max и только после первого ответа — до того этой части нет.
Ставится настройкой statusLine (nastroyki.json); session-start.sh кладёт свежую копию в постоянную
папку пакета, чтобы путь не менялся от обновлений. Команда statusLine сама находит настоящий Python
(на Windows python3 бывает заглушкой магазина Microsoft) и включает UTF-8.
"""
import json
import os
import sys
import time

DIM, RESET = "\033[2m", "\033[0m"
GREEN, YELLOW, RED = "\033[32m", "\033[33m", "\033[31m"


def color(value, yellow, red):
    return RED if value >= red else YELLOW if value >= yellow else GREEN


def size_label(n):
    return f"{n // 1_000_000}M" if n % 1_000_000 == 0 else f"{n // 1000}k"


def reset_label(ts):
    """Когда лимит обнулится: сегодня-завтра — время, дальше — дата."""
    fmt = "%H:%M" if ts - time.time() < 20 * 3600 else "%d.%m"
    return time.strftime(fmt, time.localtime(ts))


def line(d):
    folder = os.path.basename((d.get("workspace") or {}).get("current_dir") or d.get("cwd") or "")
    parts = [f"{DIM}📁 {folder}{RESET}"]

    model = (d.get("model") or {}).get("display_name") or "Claude"
    effort = (d.get("effort") or {}).get("level")
    parts.append(f"🧠 {model}" + (f" {DIM}· {effort}{RESET}" if effort else ""))

    cw = d.get("context_window") or {}
    size = cw.get("context_window_size") or 200_000
    pct = cw.get("used_percentage") or 0
    used = int(pct * size / 100)
    # Жёлтый и красный — заранее, пока работа ещё не просела: с 250k и 400k, в малом окне — с половины и трёх четвертей
    c = color(used, min(250_000, size // 2), min(400_000, size * 3 // 4))
    parts.append(f"{c}📊 разговор {int(pct)}% {DIM}({used // 1000}k/{size_label(size)}){RESET}")

    limits = []
    for key, name in (("five_hour", "5ч"), ("seven_day", "неделя")):
        w = (d.get("rate_limits") or {}).get(key) or {}
        p = w.get("used_percentage")
        if p is None:
            continue
        s = f"{color(p, 50, 80)}{name} {int(p)}%{RESET}"
        if p >= 80 and w.get("resets_at"):
            s += f" {DIM}до {reset_label(w['resets_at'])}{RESET}"
        limits.append(s)
    if limits:
        parts.append("⏳ лимит " + f" {DIM}·{RESET} ".join(limits))

    return f"  {DIM}│{RESET}  ".join(parts)


if __name__ == "__main__":
    try:
        for stream in (sys.stdin, sys.stdout, sys.stderr):  # на Windows кодировка по умолчанию не UTF-8: русские буквы и значки ломались бы
            stream.reconfigure(encoding="utf-8")
        print(line(json.load(sys.stdin)), end="")
    except (ValueError, TypeError, AttributeError, OSError) as e:  # строка не должна пропасть целиком: показываем папку, причину — в stderr
        print(f"📁 {os.path.basename(os.getcwd())}", end="")
        print(f"KOROBEINIKOV AI: строка внизу не разобрала данные Claude Code: {e}", file=sys.stderr)
