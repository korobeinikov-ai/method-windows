# Лёгкий ИИ в боте

Только по просьбе человека. Бот отвечает, разбирает текст и документы. Опасных действий ИИ не делает: всё, что меняет
данные или тратит деньги, держит программа, а не инструкция.

## Честно про деньги
Ключ Anthropic оплачивается отдельно от подписки Claude. Цены сверь на https://platform.claude.com/docs/en/about-claude/pricing.
По умолчанию — Claude Haiku 5.5, самая лёгкая и дешёвая модель: примерно $0,25 за 1000 коротких сообщений, с
размышлениями модели выйдет дороже. Менять модель можно настройкой `II_MODEL`.

## Ключ и потолок (руки человека)
1. https://platform.claude.com/settings/billing: пополнить баланс.
2. Там же, в разделе Spend limits, нажать Set limit и поставить потолок. Ставь с запасом: кончились деньги — бот молчит.
3. https://platform.claude.com/settings/keys: Create Key, скопировать и написать «скопировал». В чат не вставлять.

Сам: `klyuch.py vzyat ANTHROPIC_API_KEY`, затем `klyuch.py peredat ANTHROPIC_API_KEY --service bot`. Имя — в `.env.example`.

## Как подключить
В `requirements.txt` добавь `anthropic==0.125.0`: эта версия ставится и на Mac, и на Railway. Обработчик ставь выше `lyuboe`.

```python
import anthropic

ii = anthropic.AsyncAnthropic()
MODEL = os.environ.get("II_MODEL", "claude-haiku-5-5")
INSTRUKCIYA = "Ты помощник компании ... Вот факты: ... Если ответа нет в фактах, скажи, что не знаешь."


@dp.message(F.text)
async def otvet_ii(message: Message):
    try:
        otvet = await ii.messages.create(
            model=MODEL,
            max_tokens=4096,
            system=INSTRUKCIYA,
            messages=[{"role": "user", "content": message.text}],
        )
    except anthropic.APIError:
        log.exception("ИИ не ответил")
        await message.answer("ИИ сейчас недоступен. Попробуйте позже или напишите владельцу.")
        return
    tekst = "".join(chast.text for chast in otvet.content if chast.type == "text")
    await message.answer(tekst[:4000] or "Не могу на это ответить.")
```

Бот отвечает на каждое сообщение отдельно: так дешевле и проще. Переписку он не помнит, и память пропадёт с выкладкой.

## Документы
PDF до 32 МБ ИИ читает сам, но Telegram отдаёт боту файлы только до 20 МБ. Передавай файл блоком `document` с `base64`.

## Как писать инструкцию
- На каждый частый вопрос нужен факт в инструкции или правило «скажи, что не знаешь». Чего ИИ не знает, то он уверенно придумает.
- Пиши, что делать, а не что нельзя: запрещённую фразу в кавычках он подхватывает и повторяет.
- Суммы и цены считает программа, а не ИИ: он складывает по частям и ошибается.
- Проси писать простым текстом: звёздочки разметки Telegram покажет как есть.

## Если ИИ перестал отвечать
Серия сбоев — сначала проверь лимит и ключ, потом ищи поломку. Смотри журнал и https://platform.claude.com/settings/billing.
Текст `You have reached your specified API usage limits` значит, что сработал потолок: он месячный, после поднятия бот
оживает сам. Ошибка 401 — это ключ, а не потолок: замени его.
