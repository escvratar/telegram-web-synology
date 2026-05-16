# Telegram Web A на Synology NAS

Self-hosted официальный веб-клиент Telegram ([telegram-tt](https://github.com/Ajaxy/telegram-tt))
как Docker-контейнер на Synology NAS. Настоящий веб-клиент, а не VNC/RDP.

Скрипт `setup.sh` собирает telegram-tt на самом NAS и упаковывает результат
в лёгкий nginx-образ. Сборка идёт на хосте, потому что у Docker-контейнеров
на Synology нет доступа в интернет для `npm`.

## Требования

- Synology DSM 7+ с установленным **Container Manager**
- Включённый **SSH**: Панель управления → Терминал и SNMP → Включить SSH
- ~2 ГБ свободной RAM и ~3 ГБ места на диске
- Telegram **api_id** и **api_hash** — получить на <https://my.telegram.org/apps>

## Установка

### 1. Скачать `setup.sh` на NAS

Подключитесь по SSH и скачайте скрипт прямо в терминале:

```bash
ssh ВАШ_ПОЛЬЗОВАТЕЛЬ@IP_NAS
mkdir -p /volume1/docker/telegram && cd /volume1/docker/telegram
curl -fsSL -O https://raw.githubusercontent.com/escvratar/telegram-web-synology/main/setup.sh
```

> **Windows без терминала:** можно использовать `deploy.bat` из репозитория —
> он сам скопирует `setup.sh` на NAS по SSH (спросит IP, логин и пароль).

### 2. Запустить установку

```bash
bash /volume1/docker/telegram/setup.sh
```

Скрипт спросит путь, `api_id`, `api_hash` и порт. Первая сборка —
**15–30 минут**, повторные быстрее (зависимости кэшируются).

### 3. Настроить обратный прокси (обязательно)

Контейнер отдаёт HTTP, но Telegram Web работает только по HTTPS
(нужен secure context). HTTPS даёт встроенный в DSM обратный прокси.

**Панель управления → Портал входа → Дополнительно → Обратный
прокси-сервер → Создать:**

| Поле                 | Значение                                   |
|----------------------|--------------------------------------------|
| Источник: протокол   | HTTPS                                      |
| Источник: имя хоста  | ваш домен, напр. `telegram.nas.synology.me`|
| Источник: порт       | свободный, напр. `4431`                    |
| Назначение: протокол | HTTP                                       |
| Назначение: хост     | `localhost`                                |
| Назначение: порт     | `4430` (порт контейнера)                   |

На вкладке **«Пользовательский заголовок»** → Создать → **WebSocket**.
Сертификат назначьте в **Безопасность → Сертификат** (подойдёт
бесплатный Let's Encrypt).

Открывайте Telegram по адресу прокси: `https://telegram.nas.synology.me:4431`

## Управление

В каталоге установки (по умолчанию `/volume1/docker/telegram-web`):

```bash
docker compose down       # остановить
docker compose up -d      # запустить
docker compose logs -f    # логи
```

Обновить telegram-tt: `rm -rf .build` и снова запустить `setup.sh`.

## Дисклеймер

Неофициальный проект. Telegram Web A и торговая марка Telegram принадлежат
Telegram. `api_id`/`api_hash` привязаны к вашему аккаунту — не публикуйте их.
Используйте на свой страх и риск.
