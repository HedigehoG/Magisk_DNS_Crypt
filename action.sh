#!/system/bin/sh

#STAMP_SCRIPT="$MODDIR/scripts/update_dns_stamp.sh"
#LOG="/data/local/tmp/dnsproxy.log"

# Простейшее переключение — если уже запущено, останавливаем
if pgrep -f dnsproxy > /dev/null; then
    echo "[*] dnsproxy уже запущен. Останавливаем..."
    pkill -f dnsproxy
    echo "Статус: остановлен"
else
    #echo "[*] Обновление DNS Stamp..."
    #sh "$STAMP_SCRIPT"

    echo "[*] Запуск dnsproxy..."
    nohup doh_client
    #nohup "$BIN" "$CONF" > /dev/null 2>&1 &
    echo "Статус: запущен"
fi
