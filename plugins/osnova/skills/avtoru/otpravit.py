#!/usr/bin/env python3
"""Отправляет заметку автору пакета — в личный закрытый приёмник участника на GitHub
(korobeinikov-ai/zametki-<логин>: видят только участник и автор).

  otpravit.py --gde "<навык и шаг>" --tip затык|запрос|удача   < текст
  otpravit.py --zametki     — накопленные заметки (~/vibecoding/zametki-dlya-avtora.md); ушли — файл удаляется

Перед отправкой: длина, сторож секретов (gitleaks), домашняя папка → «~».
Код выхода: 0 — ушло; 1 — не ушло (текст сохранён в заметки, причина в ответе); 2 — текст не принят.
"""
import datetime
import os
import platform
import re
import subprocess
import sys
from pathlib import Path

ORG = "korobeinikov-ai"
NOTES = Path.home() / "vibecoding" / "zametki-dlya-avtora.md"
ROOT = Path(__file__).resolve().parents[2]
os.environ["NoDefaultCurrentDirectoryInExePath"] = "1"  # Windows не ищет программы в текущей папке (там может лежать подмена)
TIPS = ("затык", "запрос", "удача")
LIMIT = 3000


def nayti(imya):
    """Полный путь к программе: ~/.local/bin, папки из PATH (только полные пути) и обычное место Git.
    Текущую папку не смотрим: Windows ищет голое имя сначала в ней, а в чужом проекте там может лежать подмена.
    Не нашли — None: голое имя не запускаем."""
    suffiks = ".exe" if os.name == "nt" else ""
    papki = [Path.home() / ".local" / "bin",
             *(Path(p) for p in os.environ.get("PATH", "").split(os.pathsep) if p and Path(p).is_absolute()),
             *(Path(os.environ[v]) / "Git" / "cmd" for v in ("ProgramFiles", "ProgramW6432") if os.environ.get(v))]
    return next((str(p / f"{imya}{suffiks}") for p in papki if (p / f"{imya}{suffiks}").is_file()), None)


def run(args, inp=None):
    programma = nayti(args[0])
    if not programma:
        return 1, f"нет программы {args[0]}"
    try:
        r = subprocess.run([programma, *args[1:]], input=inp, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=60, check=False)
        return r.returncode, (r.stdout + r.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)


def opt(argv, name):
    return argv[argv.index(name) + 1].strip() if name in argv and argv.index(name) + 1 < len(argv) else ""


def footer():
    ver = ROOT.name  # установленный пакет лежит в папке с именем версии
    if not re.fullmatch(r"[0-9a-f]{7,40}", ver):
        code, out = run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"])
        ver = out if code == 0 else "?"
    code, out = run(["claude", "--version"])
    cc = out.split()[0] if code == 0 and out else "?"
    return f"пакет {ver} · {platform.platform(terse=True)} · Claude Code {cc} · {datetime.date.today():%d.%m.%Y}"


def save_locally(gde, tip, text):
    NOTES.parent.mkdir(parents=True, exist_ok=True)
    line = " ".join(text.split())[:300]
    with NOTES.open("a", encoding="utf-8") as f:
        f.write(f"{datetime.date.today():%d.%m.%Y} | {gde} | {tip} | {line} (не ушло автору — отправить позже)\n")


def main(argv):
    for potok in (sys.stdin, sys.stdout):  # Windows без этого ломает русские буквы и значки
        potok.reconfigure(encoding="utf-8", errors="replace")
    from_notes = "--zametki" in argv
    if from_notes:
        text = NOTES.read_text(encoding="utf-8").strip() if NOTES.is_file() else ""
        if not text:
            print("Заметок для автора нет — отправлять нечего.")
            return 0
        n = sum(1 for s in text.splitlines() if "|" in s)
        gde, tip, title = "заметки по ходу работы", "заметки", f"Заметки для автора: {n}"
    else:
        gde, tip, text = opt(argv, "--gde"), opt(argv, "--tip"), sys.stdin.read().strip()
        if tip not in TIPS or not gde or len(gde) > 80 or not text:
            print(f"❌ Нужно: --gde «навык и шаг» (до 80 знаков), --tip {' | '.join(TIPS)} и текст во входе.")
            return 2
    text = text.replace(str(Path.home()), "~").replace(Path.home().as_posix(), "~")
    if not from_notes:
        title = f"{tip}: {gde} — {text.splitlines()[0][:60]}"
    if len(text) > LIMIT:
        print(f"❌ Слишком длинно ({len(text)} знаков, можно до {LIMIT}) — сократи до сути.")
        return 2

    if not nayti("gitleaks"):
        reason = f"нет сторожа секретов — запусти: bash {ROOT.as_posix()}/skills/start/instrumenty.sh"
    else:
        code, _ = run(["gitleaks", "stdin", "--no-banner", "--redact", "--config", str(ROOT / "skelet" / ".gitleaks.toml")], text)
        if code == 1:
            print("❌ В тексте что-то похожее на ключ или пароль — убери его и отправь снова. Ничего не ушло.")
            return 2
        reason = None if code == 0 else f"сторож секретов не запустился (код {code})"

    url = None
    if not reason:
        code, login = run(["gh", "api", "user", "--jq", ".login"])
        if not nayti("gh"):
            reason = f"нет программы gh — запусти: bash {ROOT.as_posix()}/skills/start/instrumenty.sh"
        elif code != 0 or not re.fullmatch(r"[A-Za-z0-9-]+", login):
            reason = "нет входа в GitHub — набери `! gh auth login --web --git-protocol https`"
        else:
            body = f"**Где:** {gde}\n**Тип:** {tip}\n\n{text}\n\n---\n<sub>{footer()}</sub>\n"
            code, out = run(["gh", "issue", "create", "-R", f"{ORG}/zametki-{login}", "--title", title,
                             "--body-file", "-"], body)
            if code == 0:
                url = out.splitlines()[-1]
            elif "Could not resolve" in out or "404" in out:
                reason = "для вас ещё не заведён приёмник заметок — напишите автору: «заведи мне приёмник заметок»"
            else:
                reason = f"GitHub не принял: {out.splitlines()[-1] if out else 'нет ответа'}"

    if url:
        if from_notes:
            NOTES.unlink()
        print(f"✅ Ушло автору: {url}")
        return 0
    if not from_notes:
        save_locally(gde, tip, text)
    print(f"❌ Не ушло: {reason}.\nТекст сохранён в заметках для автора — отправим позже.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
