#!/system/bin/sh
MODDIR=${0%/*}
LAUNCHER="$MODDIR/system/bin/doh_client"

if [ -f "$LAUNCHER" ]; then
    sh "$LAUNCHER"
else
    echo "[-] Ошибка: $LAUNCHER не найден!"
fi
