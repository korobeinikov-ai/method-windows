"""Рабочий Telegram-бот: отвечает своим, присылает пробный файл, чужих не пускает.

Новую работу добавляй обработчиками ниже. Пропуск стоит перед всеми сразу, забыть его нельзя.
Новый обработчик сообщений ставь выше `lyuboe`: тот забирает всё, что не подошло другим.
"""
import asyncio
import io
import logging
import os
import re
import sys

from aiogram import BaseMiddleware, Bot, Dispatcher, F
from aiogram.filters import CommandStart
from aiogram.types import (
    BufferedInputFile,
    CallbackQuery,
    ErrorEvent,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    Message,
)
from openpyxl import Workbook

log = logging.getLogger("bot")
dp = Dispatcher()
POHOZHE_NA_KLYUCH = re.compile(r"\d{6,}:[\w-]{30,}|sk-ant-[\w-]+")
KNOPKI =InlineKeyboardMarkup(
    inline_keyboard=[[InlineKeyboardButton(text="Прислать пробный файл", callback_data="proba")]]
)


def svoi():
    """Номера своих людей из настройки TELEGRAM_SVOI: через запятую, первый — владелец. Опечатка бота не роняет."""
    return {int(n) for n in os.environ.get("TELEGRAM_SVOI", "").split(",") if n.strip().isdigit()}


class BezKlyucha(logging.Formatter):
    """Ключи не попадают в журнал, даже внутри текста ошибки: ключ бота и всё, что похоже на ключ."""

    def __init__(self, klyuch):
        super().__init__("%(asctime)s %(levelname)s %(name)s: %(message)s")
        self.klyuch = klyuch

    def format(self, record):
        return POHOZHE_NA_KLYUCH.sub("***", super().format(record).replace(self.klyuch, "***"))


class Propusk(BaseMiddleware):
    """Дверь одна на всех: сообщение чужого дальше не идёт."""

    async def __call__(self, handler, event, data):
        avtor = event.from_user
        if avtor and avtor.id in svoi():
            return await handler(event, data)
        nomer = avtor.id if avtor else "неизвестен"
        log.info("Чужой написал боту, номер %s", nomer)
        if isinstance(event, Message) and event.chat.type != "private":
            return None  # в чужой группе бот молчит: номера людей там не показываем
        tekst = f"Этот бот закрытый. Ваш номер: {nomer}. Передайте его владельцу."
        if isinstance(event, CallbackQuery):
            await event.answer(tekst, show_alert=True)
        else:
            await event.answer(tekst)
        return None


dp.message.outer_middleware(Propusk())
dp.callback_query.outer_middleware(Propusk())


def probnyi_fayl():
    kniga = Workbook()
    list_ = kniga.active
    list_.append(["Проверка", "Итог"])
    list_.append(["Бот работает без вашего компьютера", "Да"])
    list_.column_dimensions["A"].width = 40
    bufer = io.BytesIO()
    kniga.save(bufer)
    return bufer.getvalue()


@dp.message(CommandStart())
async def start(message: Message):
    await message.answer("Я на связи и работаю без вашего компьютера.", reply_markup=KNOPKI)


@dp.callback_query(F.data == "proba")
async def proba(zapros: CallbackQuery, bot: Bot):
    await zapros.answer()
    await bot.send_document(zapros.from_user.id, BufferedInputFile(probnyi_fayl(), filename="proba.xlsx"))


@dp.message()
async def lyuboe(message: Message):
    await message.answer("Я на связи.", reply_markup=KNOPKI)


@dp.errors()
async def oshibka(sobytie: ErrorEvent, bot: Bot):
    log.error("Ошибка в боте", exc_info=sobytie.exception)
    avtor = getattr(sobytie.update.event, "from_user", None)
    if avtor:
        await bot.send_message(avtor.id, "Не получилось: записал ошибку в журнал. Попробуйте ещё раз чуть позже.")
    return True


async def main():
    klyuch = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not klyuch:
        sys.exit("Нет настройки TELEGRAM_BOT_TOKEN: бот не может запуститься")
    # Журнал идёт в обычный вывод: Railway помечает как ошибку всё, что пишут в поток ошибок.
    vyvod = logging.StreamHandler(sys.stdout)
    vyvod.setFormatter(BezKlyucha(klyuch))
    logging.basicConfig(level=logging.INFO, handlers=[vyvod])
    logging.getLogger("httpx").setLevel(logging.WARNING)  # адреса запросов в журнал не пишем: в них бывают ключи
    log.info("Бот запущен, своих людей: %s", len(svoi()))
    await dp.start_polling(Bot(klyuch))


if __name__ == "__main__":
    asyncio.run(main())
