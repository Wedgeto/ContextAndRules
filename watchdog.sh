#!/bin/bash

# ==========================================
# Antigravity Swarm Watchdog (V5)
# ==========================================

# Директории шины данных
OUTBOX="docs/agent/exchange/outbox"
INBOX="docs/agent/exchange/inbox"
ARCHIVE="docs/agent/exchange/archive"

# Создаем структуру, если ее нет
mkdir -p "$OUTBOX" "$INBOX" "$ARCHIVE"

echo "[*] Watchdog запущен. Мониторинг директории: $OUTBOX"
echo "[*] Для остановки нажмите Ctrl+C"
echo "---------------------------------------------------"

# Функция для примитивного парсинга YAML (чтобы не ставить yq)
parse_yaml() {
    local key=$1
    local file=$2
    # Ищет ключ, игнорирует пробелы, забирает все после двоеточия
    grep -E "^${key}:" "$file" | sed -E "s/^${key}:[[:space:]]*//; s/['\"]//g"
}

# Бесконечный цикл с inotifywait (ждет события close_write)
while true; do
    # inotifywait блокирует выполнение до появления нового файла
    # Если inotifywait не установлен, скрипт упадет. Убедитесь, что он есть!
    FILE_EVENT=$(inotifywait -q -e close_write --format "%w%f" "$OUTBOX")
    
    # Проходим по всем yaml в outbox (на случай если файлов упало сразу несколько)
    for TASK_FILE in "$OUTBOX"/*.yaml; do
        # Проверка, что файл существует (если папка пуста, glob вернет саму строку)
        [ -f "$TASK_FILE" ] || continue

        echo "[+] Обнаружен новый манифест: $TASK_FILE"

        # Парсим параметры
        TASK_ID=$(parse_yaml "task_id" "$TASK_FILE")
        TOOL=$(parse_yaml "target_tool" "$TASK_FILE")
        ACTION=$(parse_yaml "action" "$TASK_FILE")
        INPUT_TARGET=$(parse_yaml "input" "$TASK_FILE")
        RULE=$(parse_yaml "compression_rule" "$TASK_FILE")

        if [[ "$TOOL" == "GEMINI_CLI" ]]; then
            echo "[-] Инструмент: GEMINI_CLI. Задача ID: $TASK_ID"
            echo "[-] Действие: $ACTION | Цель: $INPUT_TARGET"
            
            # Подготовка промпта для CLI
            SYS_PROMPT="Ты DATA_MINER. Твоя цель: $ACTION. Правило: $RULE. Отвечай только по сути, без воды."
            
            # Чтение целевого файла (с защитой от чтения гигабайтных дампов)
            if [ -f "$INPUT_TARGET" ]; then
                # Берем только последние 1000 строк для логов/кода, чтобы не убить токенизатор
                DATA=$(tail -n 1000 "$INPUT_TARGET") 
            else
                DATA="Целевой файл $INPUT_TARGET не найден или это запрос к MCP."
            fi

            # Вызов gemini-cli (замените аргументы на те, что использует ваша версия CLI)
            # Предполагается, что CLI принимает промпт как аргумент или через пайп
            echo "[-] Отправка запроса в API..."
            RESULT=$(gemini-cli ask "$SYS_PROMPT. Анализируй это: $DATA")

            # Формирование ответа в inbox
            OUT_FILE="$INBOX/result_${TASK_ID}.yaml"
            echo "---" > "$OUT_FILE"
            echo "task_id: $TASK_ID" >> "$OUT_FILE"
            echo "status: success" >> "$OUT_FILE"
            echo "summary: |" >> "$OUT_FILE"
            # Добавляем отступы для многострочного YAML
            echo "$RESULT" | sed 's/^/  /' >> "$OUT_FILE"

            echo "[v] Ответ сохранен: $OUT_FILE"

        elif [[ "$TOOL" == "JULES" ]]; then
            echo "[!] Обнаружен запрос к JULES. Так как он требует ручного аппрува MR, пропускаем авто-вызов."
            # Здесь можно добавить генерацию Issue в GitLab через curl/glab cli
        else
            echo "[x] Неизвестный инструмент: $TOOL"
        fi

        # Архивация отработанного манифеста
        mv "$TASK_FILE" "$ARCHIVE/"
        echo "[*] Манифест $TASK_ID перемещен в архив."
        echo "---------------------------------------------------"
    done
done
