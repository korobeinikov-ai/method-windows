# Карта: метод KOROBEINIKOV AI для Windows

**Что это.** Версия метода для Windows 10 и 11: основа — снимок от 11.11.2026 (метка `vypusk-2026-11-11-1155`), вход
через приложение Claude — с 13.11.2026. Репо открытое: korobeinikov-ai/method-windows. Механика (установка, охрана,
проводник, скрипты) заморожена: Mac-версия живёт в мастерской и сюда сама не попадает. Исключение — заголовки навыков:
их привозит выпуск мастерской, а полные тексты на сервере знаний общие с Mac.

## Как ставится у человека
Приложение Claude → вкладка Code → фраза из `README.md` (или личный текст из бота метода) → Claude читает `CLAUDE.md` →
сам запускает `install.ps1` одной командой в фоне (видит `CLAUDE_CODE_EXECPATH`: Claude не ставит и не запускает) — Git,
Python (winget для пользователя; нет winget или не справился — установщики с сайтов программ, версии и суммы закреплены,
без окна «Разрешить»), настройки охраны (переменные пользователя и `settings.json`), полка `korobeinikov-ai-windows`, пакеты
`osnova` и `stroka`, программы пакета, автообновление, личная ссылка из `METHOD_DOSTUP` (`…/u/<ссылка>?os=windows`:
PowerShell-скрипт с сервера кладёт ключ в `~/.config/korobeinikov-ai/klyuch`, папка закрыта `icacls`), проверка охраны,
пути проводника. Пока она идёт, Claude в том же чате знакомится и спрашивает название дела; потом «да» на настройки,
проект скриптами проводника с диска (через Git Bash и `py.sh`) → один новый сеанс сразу в папке проекта (решение 14.11).
Ошибки подготовки изнутри Claude адресованы Claude («почини и запусти снова»), человеку команд не показывают.
Охрана в новом сеансе не видит Git или Python — проводник просит один раз полностью закрыть Claude и открыть снова.
Мак-фраза со страницы `korobeinikov-ai/method` на Windows тоже ведёт сюда: её инструкция отправляет Claude к `CLAUDE.md` этого репо.

## Главные файлы
- `README.md` — страница для людей: три шага установки. `CLAUDE.md` — инструкция Claude, если человек просит поставить метод.
- `install.ps1` — подготовка с чистой машины (Windows PowerShell 5.1 и 7); повторный запуск ничего не меняет.
  Без Claude (обычное окно PowerShell) ставит и запускает Claude сам.
- `.claude-plugin/marketplace.json` — полка `korobeinikov-ai-windows`: `osnova` и `stroka`.
- `plugins/osnova/hooks/` — охрана: `block-env-commit.py` (.env не в git), `verify-gate.py` («готово = доказано»),
  `verify-evidence.py`, `lint-after-edit.py`, `gitfind.py` (git только по полному пути), `py.sh` (настоящий Python),
  `session-start.sh` (правила и состояние человека в каждый сеанс), `hooks.json`.
- `plugins/osnova/.mcp.json`, `znaniya/znaniya.py` — посыльный: полный текст навыка с сервера по личному ключу. Запуск —
  Git Bash + `py.sh -I -X utf8`; команды Mac в тексте (`python3`, `.venv/bin`) переводит на Windows.
- `plugins/osnova/rules/` — `PRAVILA.md`, `WINDOWS.md` (как делать по-маковски написанное). `plugins/osnova/skelet/` — заготовка проекта.
- `plugins/osnova/skills/` — `start` (проводник, `instrumenty.sh`, `nastroyki.json`) и `avtoru` — полные, под Windows.
  `railway`, `telegram-bot`, `baza`, `premortem`, `svoy-kompyuter`, `systematic-debugging` — заголовки (их кладёт выпуск
  мастерской), рядом свои скрипты под Windows: `railway/klyuch.py` (ключи через буфер обмена и stdin), шаблон бота на aiogram.
- `plugins/stroka/` — строка над полем ввода в приложении: копия Mac-версии, от системы не зависит.
- `tests/` — `test-hooks.sh`, `test-klyuchi.sh`, `test-provodnik.sh`, `test-shablon.sh`, `test-teksty.sh`, `test-znaniya.sh`,
  `test-ustanovka.ps1`.

## Как проверять
Главная мерка — прогон на настоящей Windows: `.github/workflows/windows.yml` (windows-latest) идёт на каждый push.
Установка с чистой машины без Git и Python, повтор «изнутри Claude» (как в приложении), `claude plugin validate`,
`claude mcp list` (посыльный виден), инструменты пакета, все `tests/` в строгом режиме (нет gitleaks, ruff или node —
провал), поиск значений ключей в журналах. Условие «готово» — зелёный прогон на `main`.
Быструю проверку логики можно сделать на Mac (`bash tests/test-hooks.sh` и другие), но она Windows не заменяет.
Обычный прогон ставит метод из папки этого коммита (`METHOD_LOCAL_DIR`). Кнопка `s_github` (Run workflow) ставит
строкой из README с GitHub, как человек: её запускать после изменений установки. Окно приложения Claude прогон не видит.
Личная ссылка для Windows проверяется настоящим PowerShell в репо сервера (`korobeinikov-ai/server`, свой прогон на Windows).

## Как обновлять
Механику — только по слову автора «обнови Windows»: нужное переносится из мастерской вручную, имена полки и репо остаются
`korobeinikov-ai-windows` и `method-windows`, потом зелёный прогон. Заголовки навыков привозит `vypusk.sh` мастерской сам
(новый навык — целиком). Мастерская поменяла, как навык зовёт свои скрипты, — это тоже «обнови Windows»: скрипты здесь свои.
Единственная ветка — `main`.

## Правила
Никакого бизнеса автора, значений ключей и абсолютных путей чужих компьютеров в файлах. Тексты для человека —
простым русским. Только Windows 10/11 и стек автора (приложение Claude, Git, Python, GitHub, Railway, Supabase, Telegram).
