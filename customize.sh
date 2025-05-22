#!/system/bin/sh

# Magisk boot helper
# This script is executed by Magisk during module installation.

# !!! CHECK THE LATEST RELEASE VERSION ON https://github.com/AdguardTeam/dnsproxy/releases !!!
DNSPROXY_VERSION="v0.75.5" # Current stable version
DNSPROXY_BASE_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/$DNSPROXY_VERSION"

MODDIR=${0%/*}
ARCH=$(getprop ro.product.cpu.abi)
BIN_DIR="$MODDIR/system/bin"
CONFIG_FILE="$MODDIR/config.ini"

# --- DNS Proxy Settings ---
P_LISTEN="-l 127.0.0.1 -p 5353" # Порт, на котором будет слушать dnsproxy
P_FAIL="-f tls://dns.google -f tls://dns.adguard.com" # Порт для перенаправления запросов на случай ошибки
P_H3="--http3" # Использовать HTTP/3

# --- User Configuration ---
USER_CONFIG_PATH="/sdcard/Download/MyDoH_Config.txt" # Путь к пользовательскому файлу настроек на устройстве

# --- Default DNS Server Settings ---
DEFAULT_DNS_SERVER="https://cloudflare-dns.com/dns-query"
DEFAULT_DNS_BOOTSTRAP="1.1.1.1,1.0.0.1"

# --- Переменные для выбранного DNS ---
SELECTED_DNS_SERVER="$DEFAULT_DNS_SERVER"
SELECTED_DNS_BOOTSTRAP="$DEFAULT_DNS_BOOTSTRAP"

ui_print " "
ui_print "--------------------------------------------------"
ui_print "   Установка модуля My DoH Client"
ui_print "--------------------------------------------------"
ui_print " "

ui_print "- Проверка пользовательского файла настроек..."

# Check if user config file exists and read it
if [ -f "$USER_CONFIG_PATH" ]; then
    ui_print "- Найден пользовательский конфиг: $USER_CONFIG_PATH"
    # Attempt to convert line endings from Windows (CRLF) to Unix (LF) if 'dos2unix' is available.
    # This is a common source of issues when sourcing files in shell environments.
    if command -v dos2unix >/dev/null 2>&1; then
        dos2unix "$USER_CONFIG_PATH" >/dev/null 2>&1
        ui_print "- Конфиг файл обработан (dos2unix)."
    fi
    
    # Source the file to load variables. Variables defined in the user config will override initial values.
    . "$USER_CONFIG_PATH"

    # Process user's choice based on DNS_CHOICE variable from the config file
    case "$DNS_CHOICE" in
        1) # Cloudflare
            SELECTED_DNS_SERVER="https://cloudflare-dns.com/dns-query"
            SELECTED_DNS_BOOTSTRAP="1.1.1.1,1.0.0.1"
            ui_print "- Пользователь выбрал Cloudflare DoH."
            ;;
        2) # Google
            SELECTED_DNS_SERVER="https://dns.google/dns-query"
            SELECTED_DNS_BOOTSTRAP="8.8.8.8,8.8.4.4"
            ui_print "- Пользователь выбрал Google DoH."
            ;;
        3) # Comss
            SELECTED_DNS_SERVER="https://dns.comss.one/dns-query"
            SELECTED_DNS_BOOTSTRAP="92.38.152.163,94.103.41.132"
            ui_print "- Пользователь выбрал Comss DoH."
            ;;
        4) # Custom DoH
            if [ -n "$CUSTOM_DNS_HOST" ]; then
                ui_print "- Пользователь выбрал свой DoH: $CUSTOM_DNS_HOST"
                SELECTED_DNS_SERVER="$CUSTOM_DNS_HOST"
                if [ -n "$CUSTOM_BOOTSTRAP_IP" ]; then
                    SELECTED_DNS_BOOTSTRAP="$CUSTOM_BOOTSTRAP_IP"
                    ui_print "  С пользовательским bootstrap IP: $CUSTOM_BOOTSTRAP_IP"
                else
                    ui_print "  Используется bootstrap по умолчанию: $DEFAULT_DNS_BOOTSTRAP"
                fi
            else
                ui_print "-! Ошибка: Выбран пользовательский DNS (4), но CUSTOM_DNS_HOST не указан в файле настроек."
                ui_print "   Возврат к Cloudflare DoH по умолчанию."
                SELECTED_DNS_SERVER="$DEFAULT_DNS_SERVER"
                SELECTED_DNS_BOOTSTRAP="$DEFAULT_DNS_BOOTSTRAP"
            fi
            ;;
        *)
            ui_print "- Неверный выбор DNS_CHOICE в файле настроек или файл не содержит выбора."
            ui_print "  Используется Cloudflare DoH по умолчанию."
            ;;
    esac
else
    ui_print "- Пользовательский файл настроек не найден. Используется Cloudflare DoH по умолчанию."
fi

ui_print "- Выбранный DoH сервер: $SELECTED_DNS_SERVER"
ui_print "- Выбранные Bootstrap IP: $SELECTED_DNS_BOOTSTRAP"

# --- Сохраняем выбранные настройки DNS в файл внутри модуля ---
# Этот файл будет прочитан service.sh при каждой загрузке
P_DNS="-u $SELECTED_DNS_SERVER"
P_BOOTSTRAP="-b $SELECTED_DNS_BOOTSTRAP"


# Определяем URL для dnsproxy dnsproxy-linux-386-v0.75.5.tar.gz
VER_GZ="$DNSPROXY_VERSION.tar.gz"
case "$ARCH" in
  arm64-v8a) URL="dnsproxy-linux-arm64-$VER_GZ" ;;
  armeabi-v7a) URL="dnsproxy-linux-armv7-$VER_GZ" ;;
  x86_64) URL="dnsproxy-linux-386-.$VER_GZ" ;;
  *) ui_print "❌ Архитектура $ARCH не поддерживается"; exit 1 ;;
esac

# Скачиваем и распаковываем dnsproxy
ui_print "  ⬇️ Скачиваем dnsproxy..."
mkdir -p $BIN_DIR

DNSPROXY_DOWNLOAD_URL="$DNSPROXY_BASE_URL/$URL"
ui_print "- Downloading dnsproxy v$DNSPROXY_VERSION for $ARCH..."
ui_print "  From: $DNSPROXY_DOWNLOAD_URL"

# Пробуем скачать через curl или wget
TMP_DIR="$MODDIR/tmp"
mkdir -p $TMP_DIR
if command -v curl >/dev/null; then
  curl -L $DNSPROXY_DOWNLOAD_URL -o $TMP_DIR/dnsproxy.tar.gz
elif command -v wget >/dev/null; then
  wget $DNSPROXY_DOWNLOAD_URL -O $TMP_DIR/dnsproxy.tar.gz
else
  ui_print "❌ Ошибка: не найден curl или wget"
  exit 1
fi

if [ $? -ne 0 ]; then
  ui_print "❌ Ошибка загрузки dnsproxy"
  exit 1
fi

tar -xzf $TMP_DIR/dnsproxy.tar.gz -C $TMP_DIR
mv $TMP_DIR/*/dnsproxy $BIN_DIR/dnsproxy
chmod 755 $BIN_DIR/dnsproxy
# Очистка
rm -rf $TMP_DIR

# Создаем файл конфигурации
cat > $CONFIG_FILE <<EOF
$P_LISTEN \\
$P_DNS \\
$P_H3 \\
$P_BOOTSTRAP \\
$P_FAIL
EOF

# Создаем скрипт запуска с поддержкой команд start, stop, renew
cat > $BIN_DIR/doh_client <<'EOF'
#!/system/bin/sh

SCRIPT_PATH="$0"
if [ -L "$0" ]; then
    SCRIPT_PATH="$(readlink -f "$0")"
fi
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONFIG_FILE="$SCRIPT_DIR/../config.ini"
USER_CONFIG="/sdcard/Download/MyDoH_Config.txt"
PID_FILE="/data/local/tmp/dnsproxy.pid"

start_dnsproxy() {
    ARGS=$(tr '\n' ' ' < "$CONFIG_FILE")
    "dnsproxy" $ARGS &
    echo $! > "$PID_FILE"
    echo "dnsproxy started (PID $(cat $PID_FILE))"
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
}

stop_dnsproxy() {
    if [ -f "$PID_FILE" ]; then
        kill "$(cat $PID_FILE)" 2>/dev/null
        rm -f "$PID_FILE"
        echo "dnsproxy stopped"
        iptables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 5353
        iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
    else
        echo "dnsproxy is not running"
    fi
}

renew_config() {
    if [ -f "$USER_CONFIG" ]; then
        # Обновить config.ini, перечитав пользовательский конфиг
        # Можно просто перезапустить customize.sh, но здесь только echo для примера
        echo "Please reinstall the module to apply new settings from $USER_CONFIG"
    else
        echo "User config not found: $USER_CONFIG"
    fi
}

o_echo() {
    echo "SCRIPT_PATH: $SCRIPT_PATH"
    echo "MODDIR: $MODDIR"
}
case "$1" in
    start)
        start_dnsproxy
        ;;
    stop)
        stop_dnsproxy
        ;;
    renew)
        renew_config
        ;;
    o)
        o_echo
        ;;
    *)
        echo "Usage: $0 {start|stop|renew|o}"
        ;;
esac
EOF

chmod 755 $BIN_DIR/doh_client

ui_print " "
ui_print "--------------------------------------------------"
ui_print "   ✅ Установка завершена!"
ui_print "   Для установки своего DNS, создайте файл:"
ui_print "   /sdcard/Download/MyDoH_Config.txt"
ui_print "   (см. README для примера содержимого)"
ui_print "--------------------------------------------------"
ui_print " "