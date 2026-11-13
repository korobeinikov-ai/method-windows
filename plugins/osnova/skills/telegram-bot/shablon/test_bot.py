"""Проверка бота без Telegram и без ключа: запуск — python -m unittest."""
import asyncio
import io
import logging
import os
import unittest
from unittest.mock import AsyncMock, MagicMock

import main
from aiogram.types import Message
from openpyxl import load_workbook

NASH, CHUZHOI = 111, 222


def soobshchenie(nomer, chat="private"):
    s = MagicMock(spec=Message)
    s.from_user = MagicMock(id=nomer)
    s.chat = MagicMock(type=chat)
    s.answer = AsyncMock()
    return s


class Propusk(unittest.TestCase):
    def setUp(self):
        os.environ["TELEGRAM_SVOI"] = f"{NASH}, 333"

    def test_svoy_prohodit(self):
        dalshe = AsyncMock()
        asyncio.run(main.Propusk()(dalshe, soobshchenie(NASH), {}))
        dalshe.assert_awaited_once()

    def test_opechatka_v_spiske_ne_ronyaet_bota(self):
        os.environ["TELEGRAM_SVOI"] = f"{NASH}, опечатка"
        dalshe = AsyncMock()
        asyncio.run(main.Propusk()(dalshe, soobshchenie(NASH), {}))
        dalshe.assert_awaited_once()

    def test_chuzhoy_vidit_svoy_nomer_i_dalshe_ne_idet(self):
        dalshe, s = AsyncMock(), soobshchenie(CHUZHOI)
        asyncio.run(main.Propusk()(dalshe, s, {}))
        dalshe.assert_not_awaited()
        self.assertIn(str(CHUZHOI), s.answer.await_args.args[0])

    def test_v_chuzhoy_gruppe_bot_molchit(self):
        s = soobshchenie(CHUZHOI, chat="group")
        asyncio.run(main.Propusk()(AsyncMock(), s, {}))
        s.answer.assert_not_awaited()

    def test_pustoy_spisok_nikogo_ne_puskaet(self):
        os.environ["TELEGRAM_SVOI"] = ""
        dalshe = AsyncMock()
        asyncio.run(main.Propusk()(dalshe, soobshchenie(NASH), {}))
        dalshe.assert_not_awaited()


class Fayl(unittest.TestCase):
    def test_probnyi_fayl_otkryvaetsya(self):
        kniga = load_workbook(io.BytesIO(main.probnyi_fayl()))
        self.assertEqual(kniga.active["A1"].value, "Проверка")


class Zhurnal(unittest.TestCase):
    def test_klyuch_ne_popadaet_v_zhurnal(self):
        klyuch = "proba-" + "x" * 30
        zapis = logging.LogRecord("bot", logging.ERROR, "", 0, f"адрес /bot{klyuch}/getMe", None, None)
        self.assertNotIn(klyuch, main.BezKlyucha(klyuch).format(zapis))

    def test_drugoy_klyuch_tozhe_skryt(self):
        drugoy = "sk-" + "ant-" + "x" * 30
        zapis = logging.LogRecord("bot", logging.ERROR, "", 0, f"сбой {drugoy}", None, None)
        self.assertNotIn(drugoy, main.BezKlyucha("proba").format(zapis))


if __name__ == "__main__":
    unittest.main()
