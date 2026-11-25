# Задачи поверх бота

Основу не переделывай: добавляй обработчики в `main.py` выше `lyuboe`. Пропуск своих уже стоит перед ними. На каждую
новую работу — проверка в `test_bot.py`. Суммы и итоги считает программа, цифры сверяй с тем, что назвал человек.

## Отчёт или расчёт вместо сайта
Кнопка или команда → программа считает → ответ текстом или файлом. Человек думает в кнопках, а не в командах.

```python
@dp.callback_query(F.data == "otchet")
async def otchet(zapros: CallbackQuery, bot: Bot):
    await zapros.answer()
    await bot.send_document(zapros.from_user.id, BufferedInputFile(sobrat_otchet(), filename="otchet.xlsx"))
```

Excel собирай как в маршруте «свой компьютер»: понятные заголовки, ширина колонок, итоги. Сообщение длиннее 4096
знаков Telegram не примет: длинное отправляй файлом.

## Человек присылает файл
Бот принимает файлы до 20 МБ. Больше — честно скажи об этом. Обрабатывай в памяти и отвечай готовым файлом: всё, что
положишь на диск Railway, пропадёт с новой выкладкой.

```python
@dp.message(F.document)
async def fayl(message: Message, bot: Bot):
    if message.document.file_size > 20 * 1024 * 1024:
        await message.answer("Файл больше 20 МБ: Telegram не даст боту его скачать.")
        return
    bufer = await bot.download(message.document)
    await message.answer_document(BufferedInputFile(obrabotat(bufer), filename="itog.xlsx"))
```

Бот понимает файлы того вида, под который написан. PDF-скан и произвольный документ код не прочтёт: это задача для `II.md`.

## Запуск своего процесса
Долгая работа не должна останавливать бота, поэтому она идёт отдельно. «Готово» — только после настоящего результата.

```python
@dp.callback_query(F.data == "zapusk")
async def zapusk(zapros: CallbackQuery, bot: Bot):
    await zapros.answer("Запустил")
    itog = await asyncio.to_thread(dolgaya_rabota)
    await bot.send_message(zapros.from_user.id, f"Готово: {itog}")
```

Ошибка дойдёт до общего обработчика: человек увидит «не получилось», а причина ляжет в журнал.

## Напоминание и отчёт по расписанию
Сервер живёт по своему времени, поэтому часовой пояс человека задавай явно: спроси город и поставь настройку
`CHASOVOI_POYAS`, например `Europe/Moscow`. Добавь в `requirements.txt` строку `tzdata`.

```python
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

async def kazhdyi_den(bot: Bot, poyas: ZoneInfo, chas: int, minuta: int):
    while True:
        seychas = datetime.now(poyas)
        srok = seychas.replace(hour=chas, minute=minuta, second=0, microsecond=0)
        if srok <= seychas:
            srok += timedelta(days=1)
        await asyncio.sleep((srok - seychas).total_seconds())
        for nomer in svoi():  # сбой на одном человеке не оставляет без сообщения остальных
            try:
                await bot.send_message(nomer, "Напоминание: ...")
            except Exception:
                log.exception("Напоминание не ушло, номер %s", nomer)

RASPISANIE = []  # держим ссылку, иначе Python может остановить задачу

@dp.startup()
async def po_raspisaniyu(bot: Bot):
    poyas = ZoneInfo(os.environ["CHASOVOI_POYAS"])  # нет настройки — бот не запустится, и это будет видно сразу
    RASPISANIE.append(asyncio.create_task(kazhdyi_den(bot, poyas, 9, 0)))
```

Скажи честно: попала минута напоминания на выкладку — оно пропадёт. Человек получит сообщение, только если сам хоть раз
написал боту.

## Бот в группе
В группе бот по умолчанию видит только команды. Чтобы видел всё, дай ему права администратора группы или выключи режим
приватности: BotFather, команда `/setprivacy`.

## Подключиться к другому сервису
Подключаем то, чем человек уже пользуется; сами другие сервисы не советуем. Ключ — как ключ бота: человек копирует,
`klyuch.py vzyat ИМЯ`, затем `klyuch.py peredat ИМЯ --service bot`. В коде только `os.environ["ИМЯ"]`. Сервис не ответил —
бот честно говорит, что не достал данные, и не выдаёт старое за новое.

## Данные между выкладками
Обычный файл на Railway пропадёт при новой выкладке. Хватает настроек — храни в них, как список своих людей. Нужно
копить данные — это база: скажи человеку, что понадобится, и подключай только тогда.
