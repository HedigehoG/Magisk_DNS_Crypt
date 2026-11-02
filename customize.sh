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

# Создаем рабочий скрипт запуска doh_client с динамической подгрузкой конфига
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
    echo "[*] Очистка правил iptables..."
    for proto in udp tcp; do
        while iptables -t nat -D OUTPUT -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null; do :; done
        while iptables -t nat -D PREROUTING -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null; do :; done
        while ip6tables -t nat -D OUTPUT -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null; do :; done
        while ip6tables -t nat -D PREROUTING -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null; do :; done
    done
}

apply_iptables() {
    echo "[+] Применяем правила перенаправления DNS (53 -> 5353)..."
    for proto in udp tcp; do
        iptables -t nat -A OUTPUT -p $proto --dport 53 -j REDIRECT --to-ports 5353
        iptables -t nat -A PREROUTING -p $proto --dport 53 -j REDIRECT --to-ports 5353
        ip6tables -t nat -A OUTPUT -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null
        ip6tables -t nat -A PREROUTING -p $proto --dport 53 -j REDIRECT --to-ports 5353 2>/dev/null
    done
}

load_config() {
    # Значения по умолчанию (Cloudflare)
    SELECTED_DNS="https://cloudflare-dns.com/dns-query"
    SELECTED_BOOTSTRAP="1.1.1.1,1.0.0.1"
    P_H3=""

    if [ -n "$USER_CONFIG" ] && [ -f "$USER_CONFIG" ]; then
        echo "[*] Загрузка настроек из: $USER_CONFIG"
        # Читаем переменные напрямую из конфига
        . "$USER_CONFIG" 2>/dev/null

        # Опция HTTP/3
        if [ "$USE_HTTP3" = "1" ]; then
            P_H3="--http3"
            echo "[*] HTTP/3 включен"
        else
            echo "[*] HTTP/3 выключен (HTTP/2)"
        fi

        # Выбор провайдера
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

    echo "[*] Проверка ответа локального резолвера..."
    while [ $count -lt 5 ]; do
        sleep 1
        if ! kill -0 "$1" 2>/dev/null; then
            echo "[-] Процесс dnsproxy аварийно упал!"
            [ -f "$LOG_FILE" ] && tail -n 5 "$LOG_FILE"
            return 1
        fi

        if nslookup "$host_to_test" 127.0.0.1:5353 >/dev/null 2>&1 || \
           ss -ulpn 2>/dev/null | grep -q ":5353 "; then
            echo "[+] DNS-резолвер успешно отвечает!"
            return 0
        fi
        count=$((count + 1))
    done

    echo "[-] Таймаут ожидания резолвера."
    return 1
}

start_dnsproxy() {
    stop_dnsproxy >/dev/null 2>&1
    load_config

    local ARGS="-l 127.0.0.1 -l ::1 -p 5353 -f 1.1.1.1:53 -f 8.8.8.8:53 $P_H3 $UPSTREAM_ARGS"

    echo "[*] Запуск dnsproxy..."
    $DNSPROXY_BIN $ARGS > "$LOG_FILE" 2>&1 &
    local PID=$!
    echo "$PID" > "$PID_FILE"

    if check_dns_health "$PID"; then
        apply_iptables
        echo "[✓] Magisk DNS Crypt успешно запущен и перенаправляет трафик."
    else
        echo "[!] Ошибка старта dnsproxy. Правила iptables НЕ применены."
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
        # Тумблер: если работает — глушим, если выключен — стартуем
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
