#!/usr/bin/env python3
"""PostToolUse hook: auto-lint a file right after Claude edits/writes it.

.py  -> ruff check (bugs + style, no formatting noise)
.js/.mjs/.cjs -> node --check (syntax only)
.ts/.tsx -> tsc single-file syntax check (no type resolution)

Only linters installed in trusted system folders are run (Windows: Program Files\\nodejs; on
Mac/Linux for local checks: /opt/homebrew, /usr/local, /usr/bin, /bin), plus ruff from ~/.local/bin,
where the package installs it — looked up and run with a fixed system PATH (not the session's) from
a neutral folder. Anything else — project node_modules, folders a downloaded repo could ship — is
NEVER run. No trusted tsc → TS skipped.

Windows, честно: Python (ruff) проверяется всегда. JS — только если node стоит в Program Files\\nodejs
(node из nvm или поставленный «только для меня» не найдётся). TS на Windows не проверяется вообще: tsc из npm —
файл .cmd, а .cmd и .bat мы намеренно не запускаем. В этих случаях проверка молча пропускается.

Exit 2 + stderr = feedback goes back to Claude so it fixes the issues.
Hook failure (no linter, bad input) exits 0 and says why in stderr.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

IS_WIN = os.name == "nt"

# Только системные папки (Windows: Program Files; Mac/Linux — Homebrew и встроенные, для проверки у автора).
# Всё остальное — в том числе node_modules проекта и любые папки, которые может подложить
# скачанный репо, — не запускается.
if IS_WIN:
    TRUSTED_PREFIXES = tuple(os.path.join(os.environ[v], "nodejs") for v in ("ProgramFiles", "ProgramFiles(x86)")
                             if os.environ.get(v))
    HOME = os.path.expanduser("~")
    CLEAN_PATH = os.pathsep.join(TRUSTED_PREFIXES)
else:
    import pwd
    TRUSTED_PREFIXES = ("/opt/homebrew/", "/usr/local/", "/usr/bin/", "/bin/")
    HOME = pwd.getpwuid(os.getuid()).pw_dir  # у системы, не из переменной сеанса
    CLEAN_PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
# Единственное исключение — ruff из ~/.local/bin: туда его ставит сам пакет. Ищется последним.
USER_BIN = os.path.realpath(os.path.join(HOME, ".local", "bin"))
# Проверки ищутся и запускаются ТОЛЬКО с этим путём поиска — не с путём сеанса: у tsc внутри
# `#!/usr/bin/env node`, и с путём сеанса он подхватил бы чужой node из папки проекта.
CLEAN_ENV = {"PATH": CLEAN_PATH, "HOME": os.environ.get("HOME", ""), "LANG": "en_US.UTF-8"}
if IS_WIN:
    CLEAN_ENV["SYSTEMROOT"] = os.environ.get("SYSTEMROOT", "")  # без неё программы Windows не стартуют


def win_path(path, win=IS_WIN):
    """Путь из хука -> путь для Python. Claude Code на Windows шлёт C:\\work\\x\\a.py; Git Bash
    показывает ту же папку как /c/work/x — приводим к C:/work/x. C:/... Python понимает сам."""
    if win and path:
        m = re.match(r"^/(?:cygdrive/)?([A-Za-z])(?:/(.*))?$", path)
        if m:
            return f"{m.group(1).upper()}:/{m.group(2) or ''}"
    return path


def under(path, folder):
    """path лежит внутри folder (на Windows без учёта регистра букв)."""
    f = os.path.normcase(folder)
    return os.path.normcase(path).startswith(f if f.endswith(os.sep) else f + os.sep)


def find_exe(name, search_path):
    """Программа name в папках search_path. Только .exe на Windows: ярлыки .cmd/.bat не запускаем.
    Папку сеанса, как делает shutil.which на Windows, не смотрим."""
    for folder in search_path.split(os.pathsep):
        exe = os.path.join(folder, name + (".exe" if IS_WIN else ""))
        if folder and os.path.isfile(exe) and os.access(exe, os.X_OK):
            return exe
    return None


def system_tool(name):
    """Linter found via the clean system PATH (ruff also in ~/.local/bin), really located
    in a trusted folder and not inside the session folder; otherwise None."""
    own = name == "ruff"
    found = find_exe(name, os.pathsep.join(filter(None, [CLEAN_PATH, USER_BIN])) if own else CLEAN_PATH)
    if not found:
        return None
    real = os.path.realpath(found)
    here = os.path.realpath(os.getcwd())
    trusted = [*TRUSTED_PREFIXES, *([USER_BIN] if own else [])]
    if not any(under(real, d) for d in trusted) or under(real, here):
        return None
    return found


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError as e:
        sys.stderr.write(f"lint-after-edit: непонятный вход, пропускаю: {e}\n")
        return 0

    path = win_path((data.get("tool_input") or {}).get("file_path", ""))
    if not path:
        return 0
    low = path.lower()  # на Windows файл бывает a.PY

    if low.endswith(".py"):
        tool, args = system_tool("ruff"), ["check", "--quiet", "--no-cache", os.path.abspath(path)]
    elif low.endswith((".js", ".mjs", ".cjs")):
        tool, args = system_tool("node"), ["--check", os.path.abspath(path)]
    elif low.endswith((".ts", ".tsx", ".mts", ".cts")):
        # single-file: catches syntax errors fast; --noResolve skips imports
        tool, args = system_tool("tsc"), ["--noEmit", "--noResolve", "--skipLibCheck",
                                          "--jsx", "preserve", "--target", "esnext", os.path.abspath(path)]
    else:
        return 0
    if not tool:
        return 0  # linter not installed on this computer — nothing to check

    try:
        result = subprocess.run([tool, *args], check=False, capture_output=True, text=True, encoding="utf-8",
                                errors="replace", timeout=30, env=CLEAN_ENV, cwd=tempfile.gettempdir())
    except (OSError, subprocess.SubprocessError) as e:
        sys.stderr.write(f"lint-after-edit: не смог запустить проверку {tool}: {e}\n")
        return 0

    if result.returncode != 0:
        output = (result.stdout + result.stderr).strip()
        if os.path.basename(tool).lower().startswith("tsc"):
            # single-file mode: keep only syntax errors (TS1xxx),
            # drop unresolved-import noise (TS2792 etc.)
            lines = [ln for ln in output.splitlines() if re.search(r"error TS1\d{3}:", ln)]
            if not lines:
                return 0
            output = "\n".join(lines)
        if output:
            print(f"Lint issues in {path}:\n{output[:3000]}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
