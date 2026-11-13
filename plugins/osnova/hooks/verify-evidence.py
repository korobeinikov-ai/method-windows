#!/usr/bin/env python3
"""PostToolUse hook: log "verification evidence" for verify-gate.py.

Counts as evidence (adapted from anthropics/cwc-long-running-agents):
- Bash/PowerShell commands that run/test/inspect something (tests, builds, curl, logs...)
- Read of a screenshot (.png/.jpg)

verify-gate.py consumes the log when a git commit is allowed, so every
commit needs fresh proof. Fail-open: any error exits 0.
"""
import json
import re
import sys
import tempfile
from pathlib import Path

# Windows: регистр букв не важен, у программ бывает .exe, Python запускают и как py, и через py.sh.
# Само упоминание py.sh проверкой не считается — нужен запуск скрипта (.py).
EVIDENCE_RE = re.compile(
    r"pytest|npm(\.cmd)? (test|run)|pnpm (test|run)|npx |next (build|dev)|tsc\b"
    r"|playwright|curl(\.exe)? |node(\.exe)? |python3?(\.exe)? |(?<![\w.-])py(\.exe)? |py\.sh\S*\s.*\.py\b"
    r"|railway(\.exe)? (logs|run)|psql|vitest|jest|invoke-(webrequest|restmethod|pester)"
    r"|check\.sh",  # общий прогон проверок проекта — тоже улика
    re.IGNORECASE,
)


def log_path(session_id):
    return Path(tempfile.gettempdir()) / f"claude-verify-{session_id or 'default'}.log"


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:  # noqa: BLE001
        return 0

    tool = data.get("tool_name", "")
    ti = data.get("tool_input") or {}
    entry = None

    if tool in ("Bash", "PowerShell"):  # PowerShell — запасной рубеж: охрана видит и его команды
        cmd = ti.get("command", "")
        # a git commit itself is not evidence
        if EVIDENCE_RE.search(cmd) and "git commit" not in cmd:
            entry = f"bash: {cmd[:200]}"
    elif tool == "Read":
        p = ti.get("file_path", "")
        if p.lower().endswith((".png", ".jpg", ".jpeg")):
            entry = f"screenshot: {p}"

    if entry:
        try:
            with open(log_path(data.get("session_id")), "a", encoding="utf-8") as f:
                f.write(entry + "\n")
        except OSError as e:
            sys.stderr.write(f"verify-evidence: не записал улику проверки: {e}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
