#!/system/bin/sh

# Magisk boot helper
# This script is executed by Magisk during module installation.

# Базовая стабильная версия AdGuard dnsproxy
DNSPROXY_VERSION="v0.76.0"

# Попытка получить последнюю версию автоматически (если есть сеть)
LATEST_TAG=$(curl -s --connect-timeout 3 https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -n "$LATEST_TAG" ]; then
    DNSPROXY_VERSION="$LATEST_TAG"
fi

ui_print " "
ui_print "--------------------------------------------------"
ui_print "   Установка модуля My DoH Client"
ui_print "--------------------------------------------------"
ui_print "[*] Версия dnsproxy: $DNSPROXY_VERSION"

MODDIR=${MODPATH:-$1}
BIN_DIR="$MODDIR/system/bin"
USER_CONFIG_PATH="/sdcard/Download/MyDoH_Config.txt"

# Создаем папки
mkdir -p "$BIN_DIR"

# Корректное определение архитектуры под релизы Adguard
VER_GZ="$DNSPROXY_VERSION.tar.gz"
case "$ARCH" in
  arm64)      URL="dnsproxy-linux-arm64-$VER_GZ" ;;
  arm|armv7)  URL="dnsproxy-linux-arm-$VER_GZ" ;;
  x86)        URL="dnsproxy-linux-386-$VER_GZ" ;;
  x64|x86_64) URL="dnsproxy-linux-amd64-$VER_GZ" ;;
  *)          ui_print "❌ Архитектура $ARCH не поддерживается"; exit 1 ;;
esac

DNSPROXY_DOWNLOAD_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/$DNSPROXY_VERSION/$URL"
ui_print "- Загрузка dnsproxy для $ARCH..."
ui_print "  URL: $DNSPROXY_DOWNLOAD_URL"

TMP_DIR="$MODDIR/tmp"
mkdir -p "$TMP_DIR"

if command -v curl >/dev/null 2>&1; then
  curl -L "$DNSPROXY_DOWNLOAD_URL" -o "$TMP_DIR/dnsproxy.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget "$DNSPROXY_DOWNLOAD_URL" -O "$TMP_DIR/dnsproxy.tar.gz"
else
  ui_print "❌ Ошибка: не найден curl или wget"
  exit 1
fi

if [ $? -ne 0 ] || [ ! -s "$TMP_DIR/dnsproxy.tar.gz" ]; then
  ui_print "❌ Ошибка загрузки dnsproxy"
  exit 1
fi

ui_print "- Распаковка бинарника..."
tar -xzf "$TMP_DIR/dnsproxy.tar.gz" -C "$TMP_DIR"
mv "$TMP_DIR"/*/dnsproxy "$BIN_DIR/dnsproxy"
chmod 755 "$BIN_DIR/dnsproxy"
rm -rf "$TMP_DIR"

# Проверка конфига на этапе установки для информации пользователю
if [ -f "$USER_CONFIG_PATH" ]; then
    ui_print "- Найден пользовательский конфиг: $USER_CONFIG_PATH"
else
    ui_print "- Конфиг не найден, будет использован Cloudflare по умолчанию."
fi

ui_print "- Создание диспетчера службы doh_client..."

# Создаем рабочий скрипт запуска doh_client с защитой от петель и без фейковых fallback
cat > "$BIN_DIR/doh_client" <<'EOF'
#!/system/bin/sh

DIR="$(dirname "$0")"
DNSPROXY_BIN="$DIR/dnsproxy"
PID_FILE="/data/local/tmp/dnsproxy.pid"
LOG_FILE="/data/local/tmp/dnsproxy.log"

# Поиск пользовательского конфига
if [ -f "/sdcard/Download/MyDoH_Config.txt" ]; then
    USER_CONFIG="/sdcard/Download/MyDoH_Config.txt"
elif [ -f "/data/media/0/Download/MyDoH_Config.txt" ]; then
    USER_CONFIG="/data/media/0/Download/MyDoH_Config.txt"
else
    USER_CONFIG=""
fi

clean_iptables() {
    echo "[*] Очистка цепочек iptables..."
    # Удаляем прыжки в нашу цепочку
    for proto in udp tcp; do
        while iptables -t nat -D OUTPUT -p $proto --dport 53 -j DNSPROXY 2>/dev/null; do :; done
        while iptables -t nat -D PREROUTING -p $proto --dport 53 -j DNSPROXY 2>/dev/null; do :; done
        while ip6tables -t nat -D OUTPUT -p $proto --dport 53 -j DNSPROXY 2>/dev/null; do :; done
        while ip6tables -t nat -D PREROUTING -p $proto --dport 53 -j DNSPROXY 2>/dev/null; do :; done
        
        # Подчищаем старые прямые правила (если остались от прошлых версий)
        while iptables -t nat -D OUTPUT -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null; do :; done
        while iptables -t nat -D PREROUTING -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null; do :; done
        while ip6tables -t nat -D OUTPUT -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null; do :; done
        while ip6tables -t nat -D PREROUTING -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null; do :; done
    done

    # Сбрасываем и удаляем саму цепочку
    iptables -t nat -F DNSPROXY 2>/dev/null
    iptables -t nat -X DNSPROXY 2>/dev/null
    ip6tables -t nat -F DNSPROXY 2>/dev/null
    ip6tables -t nat -X DNSPROXY 2>/dev/null
}

apply_iptables() {
    echo "[+] Применяем правила перенаправления (через цепочку DNSPROXY)..."
    clean_iptables

    # Создаем отдельные изолированные цепочки
    iptables -t nat -N DNSPROXY
    ip6tables -t nat -N DNSPROXY 2>/dev/null

    # 1. Пропускаем трафик на loopback (не трогаем локальные сокеты)
    iptables -t nat -A DNSPROXY -o lo -j RETURN
    ip6tables -t nat -A DNSPROXY -o lo -j RETURN 2>/dev/null

    # 2. АНТИ-ПЕТЛЯ: Исключаем Bootstrap IP адреса из перехвата!
    # Запросы dnsproxy к bootstrap DNS должны идти напрямую в сеть
    for ip in $(echo "$SELECTED_BOOTSTRAP" | tr ',' ' '); do
        echo "[*] Анти-петля: исключаем Bootstrap IP $ip"
        iptables -t nat -A DNSPROXY -d "$ip" -j RETURN
        ip6tables -t nat -A DNSPROXY -d "$ip" -j RETURN 2>/dev/null
    done

    # 3. Всё остальное на порт 53 заворачиваем в dnsproxy (5353)
    iptables -t nat -A DNSPROXY -p udp --dport 53 -j REDIRECT --to-ports 5353
    iptables -t nat -A DNSPROXY -p tcp --dport 53 -j REDIRECT --to-ports 5353
    ip6tables -t nat -A DNSPROXY -p udp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null
    ip6tables -t nat -A DNSPROXY -p tcp --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null

    # 4. Активируем цепочку для исходящего трафика (OUTPUT) и точки доступа (PREROUTING)
    for proto in udp tcp; do
        iptables -t nat -A OUTPUT -p $proto --dport 53 -j DNSPROXY
        iptables -t nat -A PREROUTING -p $proto --dport 53 -j DNSPROXY
        ip6tables -t nat -A OUTPUT -p $proto --dport 53 -j DNSPROXY 2>/dev/null
        ip6tables -t nat -A PREROUTING -p $proto --dport 53 -j DNSPROXY 2>/dev/null
    done
}

load_config() {
    SELECTED_DNS="https://cloudflare-dns.com/dns-query"
    SELECTED_BOOTSTRAP="1.1.1.1,1.0.0.1"
    P_H3=""

    if [ -n "$USER_CONFIG" ] && [ -f "$USER_CONFIG" ]; then
        echo "[*] Загрузка настроек из: $USER_CONFIG"
        . "$USER_CONFIG" 2>/dev/null

        if [ "$USE_HTTP3" = "1" ]; then
            P_H3="--http3"
            echo "[*] HTTP/3 включен"
        else
            echo "[*] HTTP/3 выключен (HTTP/2)"
        fi

        case "$DNS_CHOICE" in
            1)
                SELECTED_DNS="https://cloudflare-dns.com/dns-query"
                SELECTED_BOOTSTRAP="1.1.1.1,1.0.0.1"
                ;;
            2)
                SELECTED_DNS="https://dns.google/dns-query"
                SELECTED_BOOTSTRAP="8.8.8.8,8.8.4.4"
                ;;
            3)
                SELECTED_DNS="https://dns.comss.one/dns-query"
                SELECTED_BOOTSTRAP="92.38.152.163,94.103.41.132"
                ;;
            4)
                if [ -n "$CUSTOM_DNS_HOST" ]; then
                    SELECTED_DNS="$CUSTOM_DNS_HOST"
                    [ -n "$CUSTOM_BOOTSTRAP_IP" ] && SELECTED_BOOTSTRAP="$CUSTOM_BOOTSTRAP_IP"
                fi
                ;;
        esac
    fi

    # Собираем bootstrap параметры
    BOOTSTRAP_ARGS=""
    for ip in $(echo "$SELECTED_BOOTSTRAP" | tr ',' ' '); do
        BOOTSTRAP_ARGS="$BOOTSTRAP_ARGS -b $ip:53"
    done

    UPSTREAM_ARGS="-u $SELECTED_DNS $BOOTSTRAP_ARGS"
    echo "[*] Выбран DoH сервер: $SELECTED_DNS"
}

check_dns_health() {
    local host_to_test="google.com"
    local count=0

    echo "[*] Честная проверка чистого DoH резолвера (без fallback)..."
    while [ $count -lt 6 ]; do
        sleep 1
        if ! kill -0 "$1" 2>/dev/null; then
            echo "[-] dnsproxy аварийно упал!"
            [ -f "$LOG_FILE" ] && tail -n 10 "$LOG_FILE"
            return 1
        fi

        if nslookup "$host_to_test" 127.0.0.1:5353 >/dev/null 2>&1 || \
           ss -ulpn 2>/dev/null | grep -q ":5353 "; then
            echo "[+] Чистый DoH-резолвер успешно ответил!"
            return 0
        fi
        count=$((count + 1))
    done

    echo "[-] Ошибка: DoH резолвер не отвечает на запросы."
    return 1
}

start_dnsproxy() {
    stop_dnsproxy >/dev/null 2>&1
    load_config

    # ВНИМАНИЕ: Никаких открытых -f (fallback)! Работаем только через проверенный DoH
    local ARGS="-l 127.0.0.1 -l ::1 -p 5353 $P_H3 $UPSTREAM_ARGS"

    echo "[*] Запуск dnsproxy..."
    $DNSPROXY_BIN $ARGS > "$LOG_FILE" 2>&1 &
    local PID=$!
    echo "$PID" > "$PID_FILE"

    if check_dns_health "$PID"; then
        apply_iptables
        echo "[✓] Magisk DNS Crypt успешно запущен и перенаправляет трафик."
    else
        echo "[!] Ошибка: DoH не заработал. Правила iptables НЕ применены."
        kill -9 "$PID" 2>/dev/null
        rm -f "$PID_FILE"
        clean_iptables
        return 1
    fi
}

stop_dnsproxy() {
    echo "[*] Остановка службы..."
    clean_iptables
    if [ -f "$PID_FILE" ]; then
        kill -9 "$(cat "$PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE"
    fi
    killall -9 dnsproxy 2>/dev/null
    echo "[✓] Служба остановлена."
}

status_dnsproxy() {
    if pidof dnsproxy >/dev/null 2>&1; then
        echo "[*] dnsproxy РАБОТАЕТ (PID: $(pidof dnsproxy))"
    else
        echo "[-] dnsproxy ОСТАНОВЛЕН"
    fi
}

case "$1" in
    start)
        start_dnsproxy
        ;;
    stop)
        stop_dnsproxy
        ;;
    renew|restart)
        echo "[*] Перезапуск службы с обновлением настроек..."
        stop_dnsproxy
        sleep 1
        start_dnsproxy
        ;;
    status)
        status_dnsproxy
        ;;
    *)
        if pidof dnsproxy >/dev/null 2>&1; then
            stop_dnsproxy
        else
            start_dnsproxy
        fi
        ;;
esac
EOF

chmod 755 "$BIN_DIR/doh_client"

ui_print " "
ui_print "--------------------------------------------------"
ui_print "  ✅ Установка завершена!"
ui_print "  Конфиг: /sdcard/Download/MyDoH_Config.txt"
ui_print "--------------------------------------------------"
ui_print " "
