# Источники

## Коннектор Meta для ИИ-агентов
- Ads MCP Server — обзор, инструменты, доступ: https://developers.facebook.com/documentation/ads-commerce/ads-ai-connectors/ads-mcp-server/ads-mcp-server-overview
- Анонс Meta Ads AI Connectors: https://www.facebook.com/business/news/meta-ads-ai-connectors
- Справка Meta о коннекторах: https://www.facebook.com/business/help/1456422242197840

## Meta: реклама
- Meta Blueprint, Performance 5: https://www.facebookblueprint.com/student/path/253157-performance-5
- Этап обучения: https://www.facebook.com/business/help/112167992830700
- Значимые правки (сброс обучения): https://www.facebook.com/business/help/316478108955072
- Разнообразие креативов (Meta, 16.12.2025): https://www.facebook.com/business/news/demystifying-creative-diversification
- Что внутри сильной рекламы, Meta × Toluna: https://www.facebook.com/business/news/reels-creative-strategies
- Крючок в Reels: https://www.facebook.com/business/news/the-science-of-the-hook-how-to-supercharge-your-reels-performance
- A/B-тесты: https://www.facebook.com/business/help/1738164643098669 · лучшие практики: https://www.facebook.com/business/help/290009911394576
- Пересечение аудиторий в аукционе: https://www.facebook.com/business/help/537699989762051
- Требования к картинкам: https://www.facebook.com/business/ads-guide/update/image
- Требования к видео: https://www.facebook.com/business/ads-guide/update/video
- Картинки в Instagram: https://www.facebook.com/business/help/109732209367483
- Реклама в Директ, приветствие с кнопками: https://developers.facebook.com/docs/marketing-api/ad-creative/messaging-ads/click-to-instagram
- Библиотека рекламы (чужая реклама для идей): https://www.facebook.com/ads/library

## Meta: рекламные стандарты (модерация)
- Введение: https://transparency.meta.com/policies/ad-standards/
- Здоровье и красота: https://transparency.meta.com/policies/ad-standards/restricted-goods-services/health-wellness/
- Личные характеристики: https://transparency.meta.com/policies/ad-standards/objectionable-content/privacy-violations-personal-attributes/
- Нагота и взрослый контент: https://transparency.meta.com/policies/ad-standards/objectionable-content/adult-nudity-and-sexual-activity/

## Не от Meta (направление, не доказательство)
- Дэвид Огилви, «Огилви о рекламе» — конкретика, цена в объявлении, предложение важнее оформления.
- Усталость креатива: официального срока и порога у Meta нет — признаки в `CREATIVE.md` это ориентир, уточняй по цифрам бизнеса.

## Инструменты агента
- Claude Code и Chrome (`/chrome`, неполадки): https://code.claude.com/docs/en/chrome
- Claude in Chrome — разрешения на сайты: https://support.claude.com/en/articles/12902446-claude-in-chrome-permissions-guide

## Что проверено и что нет (ноябрь 2026)
- **Проверено на одном рекламном кабинете, на Mac:** подключение без своего приложения Meta (`claude mcp add` без `--client-id`,
  вход через Facebook) и вход из живого терминала; чтение данных кабинета; сборка черновика рекламы с превью и удаление черновика.
- **Windows — не проверено:** Claude Code там работает через Git Bash, команды те же; на живом Windows не запускали.
- **Не проверено:** публикация (по смыслу — одна команда `ads_activate_entity`, она под подтверждением); загрузка файла через
  коннектор — у части кабинетов Meta её ещё не включила; окно загрузки в чате — зависит от приложения; загрузка через Chrome;
  отдельные виды рекламы из таблицы в `LAUNCH.md` — собраны по описанию коннектора; видео; запланированная задача.
- Коннектор Meta — бета (анонс Meta, апрель 2026); названия и поля инструментов могут меняться — агент читает их описания сам.
- Предел 10 МБ — ограничение инструмента загрузки файлов Claude in Chrome; через коннектор — картинки до 30 МБ, видео до 500 МБ.
