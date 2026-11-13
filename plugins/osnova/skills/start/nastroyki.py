#!/usr/bin/env python3
"""Настройки «как у автора» → настройки Claude Code человека (~/.claude/settings.json).

  nastroyki.py pokazat              — что поменяется; ничего не пишет
  nastroyki.py ustanovit --data DIR — копия старых настроек → бережное слияние → запись;
                                      версия запоминается в DIR/nastroyki-versiya
  nastroyki.py otkaz --data DIR     — человек отказался: запомнить версию, чтобы не предлагать
                                      снова до следующей
  nastroyki.py obnovleniya          — только автообновление пакета (блок «vsegda»): часть
                                      установки, ставится всем, без вопроса и без версии

Слияние бережное: ничего из настроек человека не удаляется. Списки дополняются, вложенные
настройки сливаются (так остаются и служебные настройки установки Windows — блок env),
отдельные значения ставятся наши («было → станет» видно в pokazat).
Файл настроек на Windows — C:\\Users\\<имя>\\.claude\\settings.json (или в папке из CLAUDE_CONFIG_DIR).
"""
import json
import os
import shutil
import sys
import time
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent / "nastroyki.json"


def settings_path():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    return Path(base) / "settings.json"


def merge(cur, new, path, changes, zachem):
    """Слить наше `new` в настройки человека `cur`; изменения копятся в changes."""
    if (isinstance(new, dict) and cur is not None and not isinstance(cur, dict)) or \
            (isinstance(new, list) and cur is not None and not isinstance(cur, list)):
        changes.append((path, f"заменится: сейчас там не по форме ({str(cur)[:40]})"))  # не молча
        return json.loads(json.dumps(new))
    if isinstance(new, dict):
        if cur is None and explain(path, zachem) != path:  # новая, у неё есть пояснение — одной строкой
            changes.append((path, "добавится"))
            return json.loads(json.dumps(new))
        base = cur or {}
        out = dict(base)
        for k, v in new.items():
            out[k] = merge(base.get(k), v, f"{path}.{k}" if path else k, changes, zachem)
        return out
    if isinstance(new, list):
        base = cur or []
        added = [x for x in new if x not in base]
        if added:
            changes.append((path, f"добавится правил: {len(added)}"))
        return base + added
    if cur != new:
        changes.append((path, f"было: {say(cur)} → станет: {say(new)}" if cur is not None else f"станет: {say(new)}"))
    return new


def say(v):
    return {True: "да", False: "нет"}.get(v, v) if isinstance(v, bool) else v


def explain(path, zachem):
    """Самое точное пояснение для пути настройки (ищем по самому длинному началу)."""
    parts = path.split(".")
    for i in range(len(parts), 0, -1):
        if ".".join(parts[:i]) in zachem:
            return zachem[".".join(parts[:i])]
    return path


def load(only_vsegda=False):
    t = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    ours = t["vsegda"] if only_vsegda else {**t["nastroyki"], **t["vsegda"]}
    p = settings_path()
    if p.exists():
        # utf-8-sig: PowerShell любит дописывать в начало файла невидимую метку BOM — она не должна ломать чтение
        cur = json.loads(p.read_text(encoding="utf-8-sig"))  # битый файл → ошибка наверх, не трогаем
        if not isinstance(cur, dict):
            raise ValueError("в файле настроек не словарь")
    else:
        cur = {}
    changes = []
    merged = merge(cur, ours, "", changes, t["zachem"])
    return t, p, merged, changes


def write(p, merged, backup):
    """Копия старых (если есть) → запись через временный файл. OSError — наверх."""
    if backup:
        shutil.copy2(p, backup)
        p = p.resolve()  # настройки-ярлык (дотфайлы) — пишем в сам файл, ярлык не ломаем
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:  # newline: на Windows иначе в файл попадут CRLF
        f.write(json.dumps(merged, ensure_ascii=False, indent=2) + "\n")
    if p.exists():
        shutil.copymode(p, tmp)  # закрытый от чужих файл (в нём бывают ключи) остаётся закрытым
    os.replace(tmp, p)


def backup_path(p):
    if not p.exists():
        return None
    stamp = time.strftime("%Y%m%d-%H%M%S")
    b, i = p.with_name(f"settings.backup-{stamp}.json"), 1
    while b.exists():  # две записи за одну секунду не затирают первую копию
        b, i = p.with_name(f"settings.backup-{stamp}-{i}.json"), i + 1
    return b


def save_version(data_dir, version):
    d = Path(data_dir)
    d.mkdir(parents=True, exist_ok=True)
    (d / "nastroyki-versiya").write_text(str(version), encoding="utf-8")


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    data = argv[argv.index("--data") + 1] if "--data" in argv and argv.index("--data") + 1 < len(argv) else None
    if cmd not in ("pokazat", "ustanovit", "otkaz", "obnovleniya") or (cmd in ("ustanovit", "otkaz") and not data):
        print(__doc__)
        return 2
    if cmd == "otkaz":  # настройки человека не читаем — нужна только версия
        v = json.loads(TEMPLATE.read_text(encoding="utf-8"))["versiya"]
        save_version(data, v)
        print(f"Запомнил: настройки версии {v} не ставим. Передумаете — /start.")
        return 0
    try:
        t, p, merged, changes = load(only_vsegda=cmd == "obnovleniya")
    except (OSError, ValueError) as e:  # json.JSONDecodeError — подвид ValueError
        print(f"❌ Не прочитал настройки ({settings_path()}): {e}. Ничего не менял.")
        return 1
    v = t["versiya"]

    if cmd == "obnovleniya":
        if not changes:
            print("✅ Автообновление пакета уже включено.")
            return 0
        backup = backup_path(p)
        try:
            write(p, merged, backup)
        except OSError as e:
            print(f"❌ Не включил автообновление ({p}): {e}." + (f" Старые настройки целы, копия: {backup}" if backup else ""))
            return 1
        print("✅ Автообновление пакета включено: новые версии будут приходить сами при запуске Claude.")
        return 0

    if cmd == "pokazat":
        if not changes:
            print(f"Всё уже стоит как у автора (настройки версии {v}).")
            return 0
        print(f"Поменяется (настройки версии {v}):")
        seen = {}
        for path, what in changes:
            seen.setdefault(explain(path, t["zachem"]), []).append(what)
        for text, whats in seen.items():
            print(f"• {text} ({'; '.join(whats)})")
        print("Из ваших настроек ничего не удаляется; старые сохраню копией.")
        return 0

    # ustanovit
    backup = backup_path(p)
    try:
        write(p, merged, backup)
        save_version(data, v)
    except OSError as e:
        print(f"❌ Не записал настройки ({p}): {e}." + (f" Старые целы, копия: {backup}" if backup else ""))
        return 1
    print(f"✅ Настройки версии {v} поставлены ({len(changes)} изменений).")
    if backup:
        print(f"   Копия старых настроек: {backup}")
    print("   Полностью заработают со следующего запуска Claude.")
    return 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):  # русские буквы и значки не зависят от кодировки Windows
        stream.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv))
