#!/usr/bin/env python3
"""PreToolUse hook on Bash: "done = proven" gate for git commits.

Blocks `git commit` unless the session gathered verification evidence
(see verify-evidence.py) since the last allowed commit. Adapted from
anthropics/cwc-long-running-agents verify-gate.sh.

Allowed without evidence:
- docs-only changes (.md/.txt/.yml/.yaml only)
- explicit override: VERIFY_OK=1 in the command

On allow, evidence is consumed so the next commit needs fresh proof.
Fail-open on any internal error.
"""
import json
import os
import re
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


def changed_files(cwd):
    git = gitfind.find_git(cwd)  # полный путь: голое имя на Windows запустило бы git.exe из папки проекта
    if not git:
        raise OSError("программа git не найдена в обычных местах")
    r = subprocess.run(
        [git, "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "status", "--porcelain"],
        check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20,
        cwd=cwd or None,
    )
    files = []
    for line in r.stdout.splitlines():
        p = line[3:]
        if " -> " in p:
            p = p.split(" -> ")[-1]
        files.append(p.strip().strip('"'))
    return files


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:  # noqa: BLE001
        return 0

    cmd = (data.get("tool_input") or {}).get("command", "")
    if not re.search(r"\bgit\b[^|;&]*\bcommit\b", cmd, re.IGNORECASE) or "VERIFY_OK=1" in cmd:
        return 0

    try:
        files = changed_files(fix_cwd(data.get("cwd")))
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
