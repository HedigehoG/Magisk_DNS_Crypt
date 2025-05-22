#!/system/bin/sh
# Простейшее переключение — если уже запущено, останавливаем
if pgrep -f dnsproxy > /dev/null; then
    echo "[*] dnsproxy уже запущен. Останавливаем..."
    doh_client stop
    echo "Статус: остановлен"
else
    echo "[*] Запуск dnsproxy..."
    doh_client start
    echo "Статус: запущен"
fi
