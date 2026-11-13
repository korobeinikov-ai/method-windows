#!/usr/bin/env python3
"""Хук: не даёт настоящим .env попасть в git и уйти на GitHub.

Это защита от случайной ошибки Claude, не от умышленного обхода (второй слой —
сторож секретов на pre-commit в проекте). Команду до конца не разбираем — её
всегда можно записать хитрее; смотрим состояние git и ставим три рубежа:

PreToolUse (Bash: git add / commit / push) — блок, если секретный .env:
  - уже отслеживается git (утечка уже в истории; на push — последний рубеж),
  - лежит в проекте, но не закрыт .gitignore,
  - уже добавлен в коммит,
  - закрыт .gitignore, а в команде где угодно есть флаг, похожий на
    «принудительно» (-f, -fA, --f…, в том числе у соседней команды или в bash -c) —
    с запасом: ложная тревога лечится разделением команды,
PostToolUse (Bash с git) — страховка: если после команды .env оказался в индексе
  или в git, сразу говорит Claude убрать. Вместе с блоком push это и закрывает
  хитрые записи флагов, которые разбор до команды пропустит: секрет может попасть
  в локальный коммит, но Claude об этом сразу узнаёт, а на GitHub он не уйдёт.
Слова «.env» в тексте команды (описание коммита и т.п.) сами по себе не тревога.
Шаблоны (.env.example / .sample / .template / .dist) — можно.
Осознанные исключения — файл `.env-public` в корне репо (путь от корня на строку): такой .env
разрешён в git, только если ВСЕ его переменные публичные по приставке (VITE_, NEXT_PUBLIC_ …) —
их сборщик и так вшивает в сайт. Дописали туда непубличное имя — снова блок.
git запускается только по полному пути (см. gitfind.py): подложенный в проекте git.exe не сработает.
Git не найден, не ответил вовремя или упал → запись в git (add / commit / push) блокируется с понятным
сообщением, а не пропускается. «Это не репозиторий» (код ответа git) — не сбой: проверять нечего.
"""
import json
import os
import re
import shlex
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gitfind  # лежит рядом с хуком; путь добавлен строкой выше

# Windows не различает регистр в имени программы: Git.exe add, GIT commit — те же команды
GIT_WRITE = re.compile(r"\bgit\b[^|;&]*\b(add|commit|push)\b", re.IGNORECASE)
GIT_ANY = re.compile(r"\bgit\b", re.IGNORECASE)
QUOTES = "'\"`()$;&|"
ALLOW_FILE = ".env-public"
PUBLIC_PREFIXES = ("VITE_", "NEXT_PUBLIC_", "PUBLIC_", "EXPO_PUBLIC_", "REACT_APP_")
VAR_LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
SAFE_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SAFE_PATH = re.compile(r"^[A-Za-z0-9_./-]+$")
MAX_UNPUSHED = 200  # больше — не проверяем и исключение не даём
GIT_TIMEOUT = 30 if os.name == "nt" else 15  # на Windows git и антивирус медленнее, чем на Mac


class GitUnavailable(Exception):
    """git не найден, не ответил вовремя или не запустился: проверять нечем."""


def git_cmd(project=None):
    """git по полному пути и без того, что его настройки в чужом репо могут исполнить."""
    exe = gitfind.find_git(project)
    if not exe:
        raise GitUnavailable("программа git не найдена в обычных местах")
    return [exe, "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"]


def fix_cwd(path, win=os.name == "nt"):
    """Папка из хука -> путь, который понимает Python. Claude Code на Windows шлёт C:\\Users\\...,
    Git Bash показывает ту же папку как /c/Users/... — приводим к C:/Users/... Иначе git не запустится
    в нужной папке, и охрана молча ничего бы не проверила."""
    if win and path:
        m = re.match(r"^/(?:cygdrive/)?([A-Za-z])(?:/(.*))?$", path)
        if m:
            return f"{m.group(1).upper()}:/{m.group(2) or ''}"
    return path


def is_secret_env(path: str) -> bool:
    # Windows: регистр букв и слэши не важны (.ENV, app\\.Env.local), хвост из точек и пробелов отбрасывается
    base = path.strip().strip(QUOTES).replace("\\", "/").rsplit("/", 1)[-1].lower().rstrip(" .")
    if not (base == ".env" or base.startswith(".env.")):
        return False
    if base in (".env.example", ".env.sample", ".env.template"):
        return False
    return not base.endswith((".example", ".sample", ".template", ".dist"))


def looks_forced(cmd: str) -> bool:
    """Где угодно в команде есть флаг, похожий на «принудительно» (с запасом).

    Токены берутся и простым делением, и как их читает оболочка (shlex); из каждого
    выбрасываются кавычки и обратные слеши — `-\\f`, `--fo''rce`, `"-"f` тоже флаги.
    """
    try:
        lexed = shlex.split(cmd)
    except ValueError:
        lexed = []
    for raw in cmd.split() + lexed:
        t = "".join(ch for ch in raw if ch not in QUOTES + "\\")
        if t.startswith("--"):
            if len(t) >= 3 and "--force".startswith(t):
                return True
        elif t.startswith("-") and len(t) > 1 and t[1:].isalpha() and "f" in t[1:]:
            return True
    return False


def git_lines(args, cwd):
    """Run git, return output lines. «Не репозиторий» и подобное — предупреждение и []; нет git,
    таймаут и запуск не удался — GitUnavailable (запись в git при этом блокируется)."""
    try:
        out = subprocess.check_output([*git_cmd(cwd), *args], text=True, encoding="utf-8", errors="replace",
                                      timeout=GIT_TIMEOUT, cwd=cwd or None, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"block-env-commit: не смог проверить (git {' '.join(args)}): {e}\n")
        return []
    except subprocess.TimeoutExpired as e:
        raise GitUnavailable(f"git не ответил за {GIT_TIMEOUT} секунд (git {' '.join(args)})") from e
    except OSError as e:
        raise GitUnavailable(f"git не запустился: {e}") from e
    return out.splitlines()


def porcelain_path(line: str) -> str:
    p = line[3:]
    if " -> " in p:
        p = p.split(" -> ")[-1]
    return p.strip().strip('"')


def secrets(args, cwd):
    return {p for p in git_lines(args, cwd) if is_secret_env(p)}


def not_public(text):
    """Что в тексте .env не публичное: имена без публичной приставки и строки не вида ИМЯ=… .
    Пустые строки и комментарии пропускаются; всё остальное обязано быть публичной переменной."""
    issues = []
    for ln in text.splitlines():
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        m = VAR_LINE.match(ln)
        if not m:
            issues.append(None)  # строка не вида ИМЯ=… — не показываем её текст
        elif not m.group(1).startswith(PUBLIC_PREFIXES):
            issues.append(m.group(1))
    return issues


def git_version(spec, root):
    """Содержимое версии файла в git (":путь" — подготовленное, "HEAD:путь" — сохранённое) или None."""
    try:
        return subprocess.check_output([*git_cmd(root), "show", spec], cwd=root, timeout=GIT_TIMEOUT,
                                       stderr=subprocess.DEVNULL).decode("utf-8-sig")  # Блокнот пишет метку BOM
    except subprocess.CalledProcessError:
        return None  # такой версии нет


def public_ok(cwd):
    """Файлы из `.env-public`, у которых ВСЕ версии (на диске, подготовленная, сохранённая и каждая
    неотправленная в истории) состоят только из публичных переменных → (разрешённые, [нарушения]).
    Любая странность — путь вне репо, ярлык, не .env, ошибка чтения — исключение не действует."""
    top = git_lines(["rev-parse", "--show-toplevel"], cwd)
    if not top:
        return set(), []
    root = os.path.realpath(top[0])
    try:
        with open(os.path.join(root, ALLOW_FILE), encoding="utf-8-sig") as f:
            listed = [ln.strip() for ln in f if ln.strip() and not ln.lstrip().startswith("#")]
    except FileNotFoundError:
        return set(), []
    except (OSError, ValueError) as e:
        return set(), [f"{ALLOW_FILE} не прочитался ({type(e).__name__}) — исключения не действуют"]
    ok, bad = set(), []
    for n, raw in enumerate(listed, 1):
        rel = os.path.normpath(raw).replace(os.sep, "/")  # git пишет пути через «/» и на Windows
        label = rel if SAFE_PATH.match(rel) else f"строка {n} списка"
        full = os.path.join(root, rel)
        if (os.path.isabs(rel) or rel.startswith(("..", "/")) or not is_secret_env(rel) or os.path.islink(full)
                or not os.path.normcase(os.path.realpath(full)).startswith(os.path.normcase(root) + os.sep)):
            bad.append(f"{label} (неверная строка списка: нужен путь к .env внутри репо)")
            continue
        try:
            versions = []
            if os.path.exists(full):
                with open(full, encoding="utf-8-sig") as f:
                    versions.append(f.read())
            for spec in (f":{rel}", f"HEAD:{rel}"):
                v = git_version(spec, root)
                if v is not None:
                    versions.append(v)
            # отправка уносит всю неотправленную историю — проверить каждую её версию файла
            shas = subprocess.check_output(
                [*git_cmd(root), "log", "--full-history", "--format=%H", "--all", "--not", "--remotes", "--", rel],
                cwd=root, timeout=GIT_TIMEOUT * 2, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace").split()
            if len(shas) > MAX_UNPUSHED:
                raise ValueError(f"неотправленных версий больше {MAX_UNPUSHED}")
            for sha in shas:
                v = git_version(f"{sha}:{rel}", root)
                if v is not None:
                    versions.append(v)
        except (OSError, ValueError, subprocess.SubprocessError) as e:
            bad.append(f"{label} (не прочитался: {type(e).__name__} — исключение не действует)")
            continue
        issues = [i for v in versions for i in not_public(v)]
        if issues:
            names = sorted({i for i in issues if i and SAFE_NAME.match(i)})
            odd = sum(1 for i in issues if not i)
            what = ", ".join(names) + (f"{'; ' if names else ''}строк не вида ИМЯ=…: {odd}" if odd else "")
            bad.append(f"{label} (непубличное: {what})")
        elif versions:
            ok.add(rel)
    return ok, bad


def before(cmd, cwd):
    if not GIT_WRITE.search(cmd):
        return 0
    ok, bad = public_ok(cwd)
    tracked = secrets(["ls-files", "--full-name"], cwd) - ok
    unignored = {porcelain_path(ln) for ln in git_lines(["status", "--porcelain", "--untracked-files=all"], cwd)
                 if ln.startswith("??") and is_secret_env(porcelain_path(ln))} - ok
    staged = secrets(["diff", "--cached", "--name-only"], cwd) - ok
    risky = looks_forced(cmd) or "update-index" in cmd
    ignored = secrets(["ls-files", "--full-name", "--others", "--ignored", "--exclude-standard"], cwd) - ok if risky else set()

    problems = []
    if bad:
        problems.append(f"в {ALLOW_FILE} есть файлы не только с публичными переменными, исключение не действует: "
                        + "; ".join(bad) + ". Секреты из них — в переменные окружения сервиса")
    if tracked:
        problems.append("уже лежат в git — утечка уже случилась: " + ", ".join(sorted(tracked))
                        + ". Убрать из git: `git rm --cached <файл>`, вписать в .gitignore и заменить ключи")
    if unignored:
        problems.append("не закрыты .gitignore, их заберёт любой git add: " + ", ".join(sorted(unignored))
                        + ". Вписать .env в .gitignore")
    if staged - tracked:
        problems.append("добавлены в коммит: " + ", ".join(sorted(staged - tracked))
                        + ". Убрать: `git restore --staged <файл>`")
    if ignored:
        problems.append("в команде есть «принудительно» (-f) или update-index, а в проекте лежат закрытые .gitignore секреты: "
                        + ", ".join(sorted(ignored)) + ". Добавляй без -f; если -f относится к другой команде — "
                        "раздели их на две")

    if problems:
        sys.stderr.write("ЗАБЛОКИРОВАНО: секретные файлы .env рядом с git (правило безопасности).\n- "
                         + "\n- ".join(problems) + "\nВ git сохраняй только .env.example с заглушками.")
        return 2  # exit 2 = block tool call, stderr shown to Claude
    return 0


def after(cmd, cwd):
    if not GIT_ANY.search(cmd):
        return 0
    ok, _ = public_ok(cwd)
    leaked = (secrets(["ls-files", "--full-name"], cwd) | secrets(["diff", "--cached", "--name-only"], cwd)) - ok
    if leaked:
        sys.stderr.write(
            "ВНИМАНИЕ: после команды секретный .env оказался в git: " + ", ".join(sorted(leaked)) + ".\n"
            "Сейчас же: ещё не в коммите — `git restore --staged <файл>`; уже в коммите — `git rm --cached <файл>`, "
            "вписать в .gitignore и новым коммитом убрать. Если коммит уже ушёл на GitHub — ключи заменить. "
            "Отправка на GitHub заблокирована, пока .env в git.")
        return 2  # PostToolUse: stderr goes back to Claude
    return 0


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except ValueError as e:
        sys.stderr.write(f"block-env-commit: непонятный вход, пропускаю: {e}\n")
        return 0
    cmd = (data.get("tool_input") or {}).get("command", "") or ""
    cwd = fix_cwd(data.get("cwd"))
    post = data.get("hook_event_name") == "PostToolUse"
    try:
        return after(cmd, cwd) if post else before(cmd, cwd)
    except GitUnavailable as e:
        sys.stderr.write(f"block-env-commit: не смог проверить через git: {e}\n")
        if not post and GIT_WRITE.search(cmd):
            sys.stderr.write("ЗАБЛОКИРОВАНО: без проверки через git ключи могут попасть в сохранение. Повтори команду; "
                             "не помогло — скажи человеку простыми словами, что git сейчас не отвечает "
                             "(антивирус, очень большая папка или Git не установлен), и не обходи охрану.\n")
            return 2
        return 0
    except Exception as e:  # noqa: BLE001 — сбой охраны не должен молча пропускать запись в git
        sys.stderr.write(f"block-env-commit: внутренняя ошибка охраны: {type(e).__name__}: {e}\n")
        if not post and GIT_WRITE.search(cmd):
            sys.stderr.write("Запись в git заблокирована, пока охрана не работает — сообщи автору пакета.\n")
            return 2
        return 0


if __name__ == "__main__":
    sys.exit(main())
