#!/usr/bin/env python3
"""Хук: не даёт настоящим .env попасть в git и уйти на GitHub.

Это защита от случайной ошибки Claude, не от умышленного обхода (второй слой —
сторож секретов на pre-commit в проекте). Команду до конца не разбираем — её
всегда можно записать хитрее; смотрим состояние git и ставим три рубежа.

Из команды узнаём только, в какие репозитории пишет git, и проверяем каждый: папку сеанса и всё,
куда ведут cd / pushd / Set-Location, git -C, --git-dir, --work-tree (и внутри bash -c, powershell -Command,
eval, скобок). Путь через переменную, подстановку или шаблон, GIT_DIR / GIT_WORK_TREE — цель не узнать:
запись в git блокируется. git add / commit / push туда, где репозитория до команды нет (git init в той же
команде), — тоже блок.

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
# куда пишет git: разбор команды до слов, как её читает Git Bash или PowerShell
SHELL_OPS = "();<>|&\n"
SKIP_WORDS = {"{", "!", "if", "then", "else", "elif", "do", "while", "until", "time", "command", "builtin", "exec",
              "nohup"}
CD = {"cd", "chdir", "sl", "set-location", "pushd", "push-location"}
PUSH = {"pushd", "push-location"}
POP = {"popd", "pop-location"}
SHELLS = {"bash", "sh", "zsh", "dash"}
POWERSHELLS = {"powershell", "pwsh"}
GIT_VALUE_OPTS = {"-C", "--git-dir", "--work-tree", "-c", "--namespace", "--config-env"}  # значение — следующим словом
WRITE_SUBS = {"add", "commit", "push", "update-index"}
VAGUE = re.compile(r"[$`*?\[\]{}]")  # переменная, подстановка, шаблон: путь не узнать, не запустив команду
VAR_PATH = re.compile(r"^\$(?:\{(home|pwd)\}|(home|pwd))(?=$|[/\\])", re.IGNORECASE)
# текст внутри <<EOF … EOF и @' … '@ (описание коммита) — не команды: его кавычки только путают разбор.
# Есть в нём cd, -C и подобное — оставляем: вдруг это скрипт, который тут же запустят
HEREDOC = re.compile(r"(<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2[^\n]*\n)(.*?)^[ \t]*\3[ \t\r]*$",
                     re.DOTALL | re.MULTILINE)
PS_HERE = re.compile(r"@(['\"])[ \t]*\r?\n(.*?)\r?\n\1@", re.DOTALL)
GIT_ENV = re.compile(r"^(\$env:)?(GIT_DIR|GIT_WORK_TREE)(=|$)", re.IGNORECASE)
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
TARGET_HINT = re.compile(r"(?i:\b(cd|chdir|sl|pushd|popd|eval|iex|invoke-expression|set-location|push-location|"
                         r"pop-location|powershell|pwsh)\b)|-C|--chdir|--git-dir|--work-tree|(?i:GIT_DIR|GIT_WORK_TREE|PWD)")
UNKNOWN_TARGET = ("ЗАБЛОКИРОВАНО: не понял, в какой папке git запишет файлы (путь через переменную, подстановку или "
                  "шаблон, GIT_DIR / GIT_WORK_TREE), — проверить там .env нечем (правило безопасности).\n"
                  "Напиши путь к папке проекта прямо: `cd ~/vibecoding/<проект> && git add …` или "
                  "`git -C ~/vibecoding/<проект> add …`; несколько папок — отдельной командой на каждую.")
NOT_REPO = ("ЗАБЛОКИРОВАНО: git запишет в папку, где репозитория ещё нет (или нет самой папки): {}. Проверить там .env "
            "до команды нечем (правило безопасности).\nСначала отдельной командой заведи репозиторий (`git init`) и "
            ".gitignore с .env, потом добавляй и сохраняй файлы.")


class GitUnavailable(Exception):
    """git не найден, не ответил вовремя или не запустился: проверять нечем."""


def git_cmd(project=None):
    """git по полному пути и без того, что его настройки в чужом репо могут исполнить (и только команды, которые
    не читают файлы: status запустил бы фильтры из настроек репо, log — проверку подписи)."""
    exe = gitfind.find_git(project)
    if not exe:
        raise GitUnavailable("программа git не найдена в обычных местах")
    return [exe, "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "log.showSignature=false"]


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


def clean(cmd, ps=False):
    """То, что оболочка выбрасывает до разбора: перенос строки через «\\» (в PowerShell — «`»), текст heredoc
    и @' … '@, комментарии # … (только с начала слова и не в кавычках; перенос строки после комментария
    остаётся разделителем)."""
    esc = "`" if ps else "\\"  # в PowerShell обратный слэш — часть пути, а экранирует обратная кавычка
    cmd = re.sub(re.escape(esc) + r"\r?\n", "", cmd)
    if ps:
        cmd = PS_HERE.sub(lambda m: m.group(0) if TARGET_HINT.search(m.group(2)) else "''", cmd)
    else:
        cmd = HEREDOC.sub(lambda m: m.group(0) if TARGET_HINT.search(m.group(4)) else m.group(1), cmd)
    out, quote, i = [], None, 0
    while i < len(cmd):
        c = cmd[i]
        if c == esc and quote != "'":
            out.append(cmd[i:i + 2])
            i += 2
            continue
        if quote:
            quote = None if c == quote else quote
        elif c in "'\"":
            quote = c
        elif c == "#" and (i == 0 or cmd[i - 1] in " \t\r\n;&|()"):
            end = cmd.find("\n", i)
            i = len(cmd) if end < 0 else end
            continue
        out.append(c)
        i += 1
    return "".join(out)


def words(cmd, ps=False):
    """Команда → слова и знаки оболочки (&&, ;, |, скобки, перенос строки); кавычки сняты, как у оболочки."""
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=SHELL_OPS)
    lex.whitespace = " \t\r"  # перенос строки разделяет команды, как «;»
    lex.whitespace_split = True
    lex.commenters = ""  # комментарии убрал clean(): shlex срезал бы и «#» посреди слова, и перенос строки
    if ps:
        lex.escape = "`"
    return list(lex)


def prog(word):
    """Имя программы без папки, регистра и .exe: C:\\Git\\cmd\\Git.EXE → git."""
    name = word.replace("\\", "/").rsplit("/", 1)[-1].lower()
    return name.removesuffix(".exe")


def place(cur, path):
    """Путь из команды (C:\\x, C:/x, /c/x, ~, относительный) → полный путь от папки cur; None — если его не узнать,
    не запустив команду."""
    m = VAR_PATH.match(path)
    rest = path[m.end():] if m else path
    if not path or VAGUE.search(rest):
        return None
    if m:
        start = "~" if (m.group(1) or m.group(2)).lower() == "home" else cur
        if start is None:
            return None
        path = start + rest
    path = os.path.expanduser(fix_cwd(path))
    if cur:
        return os.path.normpath(os.path.join(cur, path))
    absolute = os.path.isabs(path) and (os.name != "nt" or os.path.splitdrive(path)[0])
    return os.path.normpath(path) if absolute else None


def git_target(args, cur):
    """Опции git перед подкомандой → (папка, ("--git-dir=…", "--work-tree=…"), пишет ли подкоманда в git)
    или None, если путь не узнать. Как у git: -C складываются по очереди, --git-dir и --work-tree
    считаются от итоговой папки."""
    where, given, i = cur, [], 0
    while i < len(args) and args[i].startswith("-"):
        opt, eq, val = args[i].partition("=")
        if not eq and opt in GIT_VALUE_OPTS:
            i += 1
            val = args[i] if i < len(args) else ""
        if opt == "-C":
            where = place(where, val)
        elif opt in ("--git-dir", "--work-tree"):
            given.append((opt, val))
        i += 1
    if where is None:
        return None
    opts = []
    for opt, val in given:
        full = place(where, val)
        if full is None:
            return None
        opts.append(f"{opt}={full}")
    return where, tuple(opts), i < len(args) and args[i].lower() in WRITE_SUBS


def targets(cmd, cur, ps=False, depth=0):
    """Куда в команде пишет git: ([(папка, опции git, запись ли это)], узнали ли все цели). ps — команда
    PowerShell. С запасом: и каждая папка, куда команда переходит (вдруг cd стоит после || или в скобках)."""
    cmd = clean(cmd, ps)
    try:
        toks = words(cmd, ps)
    except ValueError:  # кавычки не разобрать: без cd, -C и подобного цель — сама папка сеанса
        return [], not TARGET_HINT.search(cmd)
    found, sure, back, pushed, ws, redirect = [], True, [], [], [], False
    prev = None  # папка до последнего cd — туда ведёт «cd -»

    def simple(ws):
        nonlocal cur, sure, prev
        if any(GIT_ENV.match(w) for w in ws):
            sure = False
        while ws and (ws[0] in SKIP_WORDS or ASSIGN.match(ws[0])):
            ws = ws[1:]
        name = prog(ws[0]) if ws else ""
        if name in CD:
            args = [w for w in ws[1:] if w == "-" or not w.startswith("-")]
            if name in PUSH:
                pushed.append(cur)
            if not args:
                new = os.path.expanduser("~") if name not in PUSH else None
            else:
                new = prev if args[0] == "-" else place(cur, args[0])
            prev, cur = cur, new
            if cur:
                found.append((cur, (), False))
            return
        if name in POP:
            prev, cur = cur, (pushed.pop() if pushed else None)
            return
        here = cur
        if name == "env":  # env -C папка git … — git работает в той папке
            for j, w in enumerate(ws[1:], 1):
                opt, eq, val = w.partition("=")
                if opt in ("-C", "--chdir"):
                    here = place(cur, val if eq else (ws[j + 1] if j + 1 < len(ws) else ""))
        script, script_ps = None, ps
        if name in ("eval", "iex", "invoke-expression"):
            script = " ".join(ws[1:])
        elif name in SHELLS:
            script, script_ps = next((ws[j + 1] for j in range(1, len(ws) - 1)
                                      if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", ws[j])), None), False
        elif name in POWERSHELLS:  # -Command, -c, -com… — команда PowerShell до конца строки
            script, script_ps = next((" ".join(ws[j + 1:]) for j in range(1, len(ws) - 1)
                                      if re.fullmatch(r"[-/]c(o(m(m(a(n(d)?)?)?)?)?)?", ws[j], re.IGNORECASE)), None), True
        if script is not None:
            sub, ok = targets(script, cur, script_ps, depth + 1) if depth < 3 else ([], False)
            found.extend(sub)
            sure = sure and ok
        for j, w in enumerate(ws):
            if prog(w) == "git":
                t = git_target(ws[j + 1:], here)
                sure = sure and t is not None
                if t:
                    found.append(t)

    for t in toks:
        if t and all(c in SHELL_OPS for c in t):
            if "<" in t or ">" in t:
                redirect = True  # следующее слово — файл, не команда
            else:
                simple(ws)
                ws = []
            for c in t:
                if c == "(":
                    back.append(cur)
                elif c == ")" and back:
                    cur = back.pop()
        elif redirect:
            redirect = False
        else:
            ws.append(t)
    simple(ws)
    return found, sure


def repos(cmd, cwd, ps=False):
    """Репозитории, куда может писать команда: ([(корень, опции git)], узнали ли все цели,
    [папки, куда git add / commit / push пишет, а репозитория там до команды нет]).
    git не найден, не ответил или не запустился — GitUnavailable (запись в git при этом блокируется)."""
    base = cwd or os.getcwd()
    found, sure = targets(cmd, base, ps)
    seen, unready = {}, []
    for where, opts, write in [(base, (), False), *found]:
        out = []  # не репозиторий или папки нет: проверять нечего, а запись туда — не проверить
        try:
            if os.path.isdir(where):
                out = subprocess.check_output([*git_cmd(where), *opts, "rev-parse", "--absolute-git-dir",
                                               "--show-toplevel"], text=True, encoding="utf-8", errors="replace",
                                              timeout=GIT_TIMEOUT, cwd=where, stderr=subprocess.DEVNULL).splitlines()
        except subprocess.CalledProcessError:
            out = []  # git ответил: это не репозиторий
        except subprocess.TimeoutExpired as e:
            raise GitUnavailable(f"git не ответил за {GIT_TIMEOUT} секунд в папке {where}") from e
        except OSError as e:
            raise GitUnavailable(f"git не запустился: {e}") from e
        if len(out) == 2:
            root = os.path.realpath(out[1])
            seen[(os.path.normcase(out[0]), os.path.normcase(root))] = (
                root, (f"--git-dir={out[0]}", f"--work-tree={root}"))
        elif write and where not in unready:
            unready.append(where)
    return list(seen.values()), sure, unready


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


def git_version(spec, root, opts):
    """Содержимое версии файла в git (":путь" — подготовленное, "HEAD:путь" — сохранённое) или None."""
    try:
        return subprocess.check_output([*git_cmd(root), *opts, "show", spec], cwd=root, timeout=GIT_TIMEOUT,
                                       stderr=subprocess.DEVNULL).decode("utf-8-sig")  # Блокнот пишет метку BOM
    except subprocess.CalledProcessError:
        return None  # такой версии нет


def public_ok(root, opts):
    """Файлы из `.env-public`, у которых ВСЕ версии (на диске, подготовленная, сохранённая и каждая
    неотправленная в истории) состоят только из публичных переменных → (разрешённые, [нарушения]).
    Любая странность — путь вне репо, ярлык, не .env, ошибка чтения — исключение не действует."""
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
                v = git_version(spec, root, opts)
                if v is not None:
                    versions.append(v)
            # отправка уносит всю неотправленную историю — проверить каждую её версию файла
            shas = subprocess.check_output(
                [*git_cmd(root), *opts, "log", "--full-history", "--format=%H", "--all", "--not", "--remotes", "--", rel],
                cwd=root, timeout=GIT_TIMEOUT * 2, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace").split()
            if len(shas) > MAX_UNPUSHED:
                raise ValueError(f"неотправленных версий больше {MAX_UNPUSHED}")
            for sha in shas:
                v = git_version(f"{sha}:{rel}", root, opts)
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


def check(cmd, root, opts):
    """Что не так с .env в одном репозитории перед записью в git: [описание]."""
    ok, bad = public_ok(root, opts)
    tracked = secrets([*opts, "ls-files", "--full-name"], root) - ok
    unignored = secrets([*opts, "ls-files", "--full-name", "--others", "--exclude-standard"], root) - ok
    staged = secrets([*opts, "diff", "--cached", "--name-only"], root) - ok
    risky = looks_forced(cmd) or "update-index" in cmd
    ignored = (secrets([*opts, "ls-files", "--full-name", "--others", "--ignored", "--exclude-standard"], root) - ok
               if risky else set())

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
    return problems


def before(cmd, cwd, ps=False):
    if not GIT_WRITE.search(cmd):
        return 0
    found, sure, unready = repos(cmd, cwd, ps)
    if not sure:
        sys.stderr.write(UNKNOWN_TARGET)
        return 2
    if unready:
        sys.stderr.write(NOT_REPO.format(", ".join(unready)))
        return 2
    problems = [(f"{root}: " if len(found) > 1 else "") + p for root, opts in found for p in check(cmd, root, opts)]
    if problems:
        sys.stderr.write("ЗАБЛОКИРОВАНО: секретные файлы .env рядом с git (правило безопасности).\n- "
                         + "\n- ".join(problems) + "\nВ git сохраняй только .env.example с заглушками.")
        return 2  # exit 2 = block tool call, stderr shown to Claude
    return 0


def after(cmd, cwd, ps=False):
    if not GIT_ANY.search(cmd):
        return 0
    found, _, _ = repos(cmd, cwd, ps)  # чего не узнать, то не дало записать в git ещё до команды
    leaked = set()
    for root, opts in found:
        ok, _ = public_ok(root, opts)
        files = (secrets([*opts, "ls-files", "--full-name"], root)
                 | secrets([*opts, "diff", "--cached", "--name-only"], root)) - ok
        leaked |= {os.path.join(root, f) if len(found) > 1 else f for f in files}
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
    ps = data.get("tool_name") == "PowerShell"
    try:
        return after(cmd, cwd, ps) if post else before(cmd, cwd, ps)
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
