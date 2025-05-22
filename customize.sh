#!/system/bin/sh

# Magisk boot helper
# This script is executed by Magisk during module installation.

# !!! CHECK THE LATEST RELEASE VERSION ON https://github.com/AdguardTeam/dnsproxy/releases !!!
DNSPROXY_VERSION="v0.75.5" # Current stable version
DNSPROXY_BASE_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/$DNSPROXY_VERSION"

MODDIR=${MODPATH:-$1}
ARCH=$(getprop ro.product.cpu.abi)
BIN_DIR="$MODDIR/system/bin"
CONFIG_FILE="$MODDIR/doh_config.sh"

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
ui_print "   My DoH Client Magisk Module Installation"
ui_print "--------------------------------------------------"
ui_print " "

ui_print "- Проверка пользовательского файла настроек..."

# Проверяем, существует ли пользовательский файл настроек, и читаем его
if [ -f "$USER_CONFIG_PATH" ]; then
    ui_print "- Найден пользовательский конфиг: $USER_CONFIG_PATH"
    # Загружаем переменные из пользовательского файла
    . "$USER_CONFIG_PATH"

    # Обрабатываем выбор пользователя
    case "$DNS_CHOICE" in
        1)
            SELECTED_DNS_SERVER="https://cloudflare-dns.com/dns-query"
            SELECTED_DNS_BOOTSTRAP="1.1.1.1,1.0.0.1"
            ui_print "- Пользователь выбрал Cloudflare DoH."
            ;;
        2)
            SELECTED_DNS_SERVER="https://dns.google/dns-query"
            SELECTED_DNS_BOOTSTRAP="8.8.8.8,8.8.4.4"
            ui_print "- Пользователь выбрал Google DoH."
            ;;
        3)
            SELECTED_DNS_SERVER="https://dns.comss.one/dns-query"
            SELECTED_DNS_BOOTSTRAP="92.38.152.163,94.103.41.132"
            ui_print "- Пользователь выбрал Comss DoH."
            ;;
        4)
            if [ -n "$CUSTOM_DNS_HOST" ]; then
                ui_print "- Пользователь выбрал свой DoH: $CUSTOM_DNS_HOST"
                if curl --output /dev/null --silent --head --fail "$CUSTOM_DNS_HOST"; then
                    ui_print "  Проверка доступности DoH сервера: $CUSTOM_DNS_HOST - Успешно"
                else
                    ui_print "  Проверка доступности DoH сервера: $CUSTOM_DNS_HOST - Ошибка"
                    ui_print "  Возврат к Cloudflare DoH по умолчанию."
                    SELECTED_DNS_SERVER="$DEFAULT_DNS_SERVER"
                    SELECTED_DNS_BOOTSTRAP="$DEFAULT_DNS_BOOTSTRAP"                    
                fi
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
echo "DNSPROXY_UPSTREAM=\"$SELECTED_DNS_SERVER\"" > "$CONFIG_FILE"
echo "DNSPROXY_BOOTSTRAP_IP=\"$SELECTED_DNS_BOOTSTRAP\"" >> "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE" # Устанавливаем правильные права доступа

# Определяем URL для dnsproxy dnsproxy-linux-386-v0.75.5.tar.gz
VER_GZ="$DNSPROXY_VERSION.tar.gz"
case "$ARCH" in
  arm64-v8a) URL="dnsproxy-linux-arm64-$VER_GZ" ;;
  armeabi-v7a) URL="dnsproxy-linux-armv7-$VER_GZ" ;;
  x86_64) URL="dnsproxy-linux-386-.$VER_GZ" ;;
  *) ui_print "❌ Архитектура $ARCH не поддерживается"; exit 1 ;;
esac

# Скачиваем и распаковываем dnsproxy
ui_print "⬇️ Скачиваем dnsproxy..."
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

# Создаем скрипт запуска
cat > $BIN_DIR/doh_client <<EOF
#!/system/bin/sh
dnsproxy \\
  -l 127.0.0.1:5353 \\
  -u "$SELECTED_DNS_SERVER" \\
  --bootstrap "$SELECTED_DNS_BOOTSTRAP" \\
  --edns 
EOF

chmod 755 $BIN_DIR/doh_client

ui_print " "
ui_print "--------------------------------------------------"
ui_print "   ✅ Установка завершена!"
ui_print "   Для настройки DNS, создайте файл:"
ui_print "   /sdcard/Download/MyDoH_Config.txt"
ui_print "   (см. README для примера содержимого)"
ui_print "--------------------------------------------------"
ui_print " "