#!/system/bin/sh

# Magisk boot helper
# This script is executed by Magisk during module installation.

# !!! CHECK THE LATEST RELEASE VERSION ON https://github.com/AdguardTeam/dnsproxy/releases !!!
DNSPROXY_VERSION="0.75.5" # Current stable version
DNSPROXY_BASE_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/v$DNSPROXY_VERSION"

MODDIR=${MODPATH:-$1}
ARCH=$(getprop ro.product.cpu.abi)
BIN_DIR="$MODDIR/system/bin"
CONF_DIR="$MODDIR/config"
DNS_SERVER=""
DNS_BOOTSTRAP="" # IP для начального резолва

# Определяем URL для dnsproxy
case "$ARCH" in
  arm64-v8a) URL="dnsproxy-linux-arm64-v8a.tar.gz" ;;
  armeabi-v7a) URL="dnsproxy-linux-armv7.tar.gz" ;;
  x86_64) URL="dnsproxy-linux-x86_64.tar.gz" ;;
  *) ui_print "❌ Архитектура $ARCH не поддерживается"; exit 1 ;;
esac

# Функция выбора DNS сервера
choose_dns_server() {
  ui_print " "
  ui_print "Выберите DoH сервер:"
  ui_print "1. Cloudflare (https://cloudflare-dns.com/dns-query)"
  ui_print "2. Google (https://dns.google/dns-query)"
  ui_print "3. Comss (https://dns.comss.one/dns-query)"
  ui_print "4. Указать свой"
  ui_print " "

  while true; do
    ui_print "Введите номер (1-4):"
    read input
    
    case $input in
      1)
        DNS_SERVER="https://cloudflare-dns.com/dns-query"
        DNS_BOOTSTRAP="1.1.1.1,1.0.0.1"
        ui_print "Выбран Cloudflare DoH"
        break
        ;;
      2)
        DNS_SERVER="https://dns.google/dns-query"
        DNS_BOOTSTRAP="8.8.8.8,8.8.4.4"
        ui_print "Выбран Google DoH"
        break
        ;;
      3)
        DNS_SERVER="https://dns.comss.one/dns-query"
        DNS_BOOTSTRAP="92.38.152.163,94.103.41.132"
        ui_print "Выбран Comss DoH"
        break
        ;;
      4)
        ui_print "Введите имя DoH сервера (my.dns.com):"
        read custom_dns
        DNS_SERVER="https://$custom_dns/dns-query"
        if curl -s --head "$DNS_SERVER" | grep -q "200 OK"; then
          ui_print "Проверка успешна, сервер доступен"
        else
          ui_print "❌ Ошибка: сервер недоступен или неверный адрес"
          exit 1
        fi

        ui_print "Введите bootstrap IP (через запятую если несколько, по умолчанию 1.1.1.1):"
        read bootstrap_ip
        DNS_BOOTSTRAP="${bootstrap_ip:-1.1.1.1}"

        ui_print "Выбран пользовательский DoH: $DNS_SERVER"
        break
        ;;
      *)
        ui_print "Неверный выбор, попробуйте снова"
        ;;
    esac
  done
  
  # Сохраняем настройки
  mkdir -p $CONF_DIR
  echo "DNS_SERVER=$DNS_SERVER" > $CONF_DIR/dns_client.conf
  echo "DNS_BOOTSTRAP=$DNS_BOOTSTRAP" >> $CONF_DIR/dns_client.conf
  echo "DNS_SDNS=" > $MODDIR/dnsproxy.conf
}

# Вызываем меню выбора
choose_dns_server

# Скачиваем и распаковываем dnsproxy
ui_print "⬇️ Скачиваем dnsproxy..."
mkdir -p $BIN_DIR

DNSPROXY_DOWNLOAD_URL="$DNSPROXY_BASE_URL/$URL"
ui_print "- Downloading dnsproxy v$DNSPROXY_VERSION for $ARCH..."
ui_print "  From: $DNSPROXY_DOWNLOAD_URL"

# Пробуем скачать через curl или wget
if command -v curl >/dev/null; then
  curl -L $DNSPROXY_DOWNLOAD_URL -o $MODDIR/dnsproxy.tar.gz
elif command -v wget >/dev/null; then
  wget $DNSPROXY_DOWNLOAD_URL -O $MODDIR/dnsproxy.tar.gz
else
  ui_print "❌ Ошибка: не найден curl или wget"
  exit 1
fi

if [ $? -ne 0 ]; then
  ui_print "❌ Ошибка загрузки dnsproxy"
  exit 1
fi

tar -xzf $MODDIR/dnsproxy.tar.gz -C $BIN_DIR
mv $BIN_DIR/dnsproxy-* $BIN_DIR/dnsproxy
chmod 755 $BIN_DIR/dnsproxy

# Создаем скрипт запуска
cat > $BIN_DIR/doh_client <<EOF
#!/system/bin/sh
dnsproxy \\
  -l 127.0.0.1:5353 \\
  -u "$DNS_SERVER" \\
  --bootstrap "$DNS_BOOTSTRAP" \\
  --edns 
EOF

chmod 755 $BIN_DIR/doh_client

# Очистка
rm $MODDIR/dnsproxy.tar.gz

ui_print "✅ Установка завершена!"
ui_print "DoH сервер: $DNS_SERVER"
ui_print "Bootstrap IP: $DNS_BOOTSTRAP"