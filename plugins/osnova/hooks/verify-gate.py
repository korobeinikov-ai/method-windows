#!/usr/bin/env python3
"""PreToolUse hook on Bash: "done = proven" gate for git commits.

Blocks `git commit` unless the session gathered verification evidence
(see verify-evidence.py) since the last allowed commit. Adapted from
anthropics/cwc-long-running-agents verify-gate.sh.

Allowed without evidence:
- docs-only commit (.md/.txt/.yml/.yaml only): judged by what this command really commits —
  already staged files, `git add` in the same command, `-a`, paths after `git commit` — not by
  the whole folder (unsaved code lying next to the docs does not block them)
- explicit override: VERIFY_OK=1 in the command

On allow, evidence is consumed so the next commit needs fresh proof.
Fail-open on any internal error.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gitfind  # лежит рядом с хуком; путь добавлен строкой выше

DOCS_ONLY = (".md", ".txt", ".yml", ".yaml")


def fix_cwd(path, win=os.name == "nt"):
    """Windows: Git Bash показывает папку как /c/Users/..., а Python на Windows понимает только C:/Users/..."""
    if win and path:
        m = re.match(r"^/(?:cygdrive/)?([A-Za-z])(?:/(.*))?$", path)
        if m:
            return f"{m.group(1).upper()}:/{m.group(2) or ''}"
    return path


# у этих ключей `git commit` значение — следующим словом (если не приклеено)
COMMIT_VALUE = {"-m", "-F", "-C", "-c", "-t", "--message", "--file", "--template", "--author", "--date",
                "--reuse-message", "--reedit-message", "--fixup", "--squash", "--trailer", "--cleanup"}


def git(cwd, *args):
    exe = gitfind.find_git(cwd)  # полный путь: голое имя на Windows запустило бы git.exe из папки проекта
    if not exe:
        raise OSError("программа git не найдена в обычных местах")
    r = subprocess.run(
        [exe, "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", *args],
        check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20,
        cwd=cwd or None,
    )
    return r.stdout


def changed_files(cwd, paths=()):
    """Изменённое в папке (или только в paths), включая ещё не добавленное в git."""
    files = []
    paths = [p.replace("\\", "/") for p in paths]  # src\app.py из PowerShell — тот же путь для git
    for line in git(cwd, "status", "--porcelain", "--untracked-files=all", "--", *paths).splitlines():
        p = line[3:]
        if " -> " in p:
            p = p.split(" -> ")[-1]
        files.append(p.strip().strip('"'))
    return files


def commands(cmd):
    """Простые команды из строки (bash или PowerShell): слова до && || ; | & и перенаправлений.
    Не разобрал — ValueError."""
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.escape = ""  # обратная черта на Windows — часть пути (src\app.py), а не экранирование
    out, cur = [], []
    for w in lex:
        if w and all(ch in "&|;()<>" for ch in w):
            out.append(cur)
            cur = []
        else:
            cur.append(w)
    return [*out, cur]


def git_sub(words):
    """('add'|'commit'|…, слова после него) для команды git (и git.exe по полному пути), иначе None."""
    while words and re.match(r"^\w+=", words[0]):  # NAME=значение перед командой
        words = words[1:]
    if not words or re.split(r"[\\/]", words[0])[-1].lower() not in ("git", "git.exe"):
        return None
    i = 1
    while i < len(words) and words[i].startswith("-"):
        i += 2 if words[i] in ("-c", "-C") else 1
    return (words[i].lower(), words[i + 1:]) if i < len(words) else None


def committed_files(cmd, cwd):
    """Что уйдёт в коммит этой командой: уже добавленное + `git add` до коммита в той же команде + `-a` (всё
    изменённое из отслеживаемого); пути после `git commit` — только они. Не разобрал команду — None."""
    files = set(git(cwd, "diff", "--cached", "--name-only").splitlines())
    for words in commands(cmd):
        sub = git_sub(words)
        if not sub:
            continue
        name, args = sub
        if name == "add":
            files |= set(changed_files(cwd, [a for a in args if not a.startswith("-")]))
        elif name == "commit":
            vse, dobavit, puti, skip, konets = False, False, [], False, False
            for a in args:
                if skip:
                    skip = False
                elif konets or not a.startswith("-") or a == "-":
                    puti.append(a)
                elif a == "--":
                    konets = True
                elif a.startswith("--"):
                    vse |= a == "--all"
                    dobavit |= a == "--include"
                    skip = a in COMMIT_VALUE
                else:  # склеенные короткие: -am "текст", -mтекст
                    for j, ch in enumerate(a[1:], 1):
                        vse |= ch == "a"
                        dobavit |= ch == "i"
                        if ch in "mFCct":
                            skip = j == len(a) - 1
                            break
            if vse:
                files |= set(git(cwd, "diff", "--name-only").splitlines())
            if puti:
                tolko = set(changed_files(cwd, puti))
                files = files | tolko if dobavit else tolko
            return {f for f in files if f}
    return None


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:  # noqa: BLE001
        return 0

    cmd = (data.get("tool_input") or {}).get("command", "")
    if not re.search(r"\bgit\b[^|;&]*\bcommit\b", cmd, re.IGNORECASE) or "VERIFY_OK=1" in cmd:
        return 0

    try:
        cwd = fix_cwd(data.get("cwd"))
        try:
            files = committed_files(cmd, cwd)
        except ValueError:  # кавычки не сошлись — команду не разобрать
            files = None
        if files is None:  # не видно, что сохраняется, — по всей папке, как раньше
            files = changed_files(cwd)
        if files and all(f.lower().endswith(DOCS_ONLY) for f in files):
            return 0
        log = Path(tempfile.gettempdir()) / f"claude-verify-{data.get('session_id') or 'default'}.log"
        if log.exists() and log.stat().st_size > 0:
            log.write_text("")  # consume: next commit needs fresh proof
            return 0
    except Exception as e:  # noqa: BLE001
        sys.stderr.write(f"verify-gate: не смог проверить, пропускаю: {type(e).__name__}: {e}\n")
        return 0

    print(json.dumps({
        "decision": "block",
        "reason": (
            "Готово = доказано: с прошлого коммита не было ни одной проверки "
            "(запуск/тест/сборка/скриншот). Сначала проверь правку делом и убедись, "
            "что она работает, потом коммить. Проверить нельзя — честно скажи человеку, "
            "что не проверено, и только после его «да» сохрани с приставкой VERIFY_OK=1."
        ),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
