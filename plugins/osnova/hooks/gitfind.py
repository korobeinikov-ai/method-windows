"""Поиск программы git для сторожей: всегда полным путём, никогда голым именем.

Windows, запуская программу по голому имени, ищет её сначала в текущей папке, а сторож запускается
именно в папке проекта. Скачанный проект с файлом git.exe в корне получил бы запуск этого файла на первом же
`git add`, и подложенный git мог бы ответить «ничего нет», обойдя охрану .env. Поэтому:
  - git ищем по полному пути: обычные места установки Git for Windows, потом папки из PATH,
    но только полные пути и не папку проекта;
  - не нашли — это «нет git», а не повод запустить голое имя;
  - в окружении процесса включаем NoDefaultCurrentDirectoryInExePath: Windows тогда вообще не смотрит
    в текущую папку (на случай, если сторож запустит что-то ещё).
"""
import os

IS_WIN = os.name == "nt"
if IS_WIN:
    os.environ["NoDefaultCurrentDirectoryInExePath"] = "1"


def _absolute(path):
    if IS_WIN:
        drive, rest = os.path.splitdrive(path)
        return bool(drive) and rest[:1] in ("\\", "/")
    return path.startswith("/")


def _trusted_dirs():
    """Куда Git for Windows ставится сам (для всех пользователей и только для одного)."""
    if not IS_WIN:
        return []
    found = []
    for var, sub in (("ProgramFiles", "Git\\cmd"), ("ProgramW6432", "Git\\cmd"), ("ProgramFiles(x86)", "Git\\cmd"),
                     ("LOCALAPPDATA", "Programs\\Git\\cmd")):
        base = os.environ.get(var)
        if base:
            found.append(os.path.join(base, sub))
    return found


def find_git(project=None):
    """Полный путь к git или None. Папки проекта (текущая и project) пропускаются, даже если стоят в PATH."""
    try:
        here = os.getcwd()
    except OSError:  # папку сеанса уже удалили
        here = None
    skip = {os.path.normcase(os.path.realpath(p)) for p in (here, project) if p}
    path_dirs = [d for d in os.environ.get("PATH", "").split(os.pathsep) if d and _absolute(d)]
    name = "git.exe" if IS_WIN else "git"
    for folder in [*_trusted_dirs(), *path_dirs]:
        if os.path.normcase(os.path.realpath(folder)) in skip:
            continue
        exe = os.path.join(folder, name)
        if os.path.isfile(exe) and os.access(exe, os.X_OK):
            return exe
    return None
