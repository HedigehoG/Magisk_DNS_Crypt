#!/system/bin/sh
# Обновление DNS stamp для dnsproxy 
# в разработке
MODDIR=${0%/*}
CONF="$MODDIR/dns_serv.conf"

echo "[*] Получаем SPKI hash для $HOST..."

HASH=$(echo | openssl s_client -connect "$HOST:$PORT" -servername "$HOST" 2>/dev/null \
  | openssl x509 -pubkey \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | base64 | tr -d '=' | tr '/+' '_-')

if [ -z "$HASH" ]; then
  echo "[!] Не удалось получить SPKI хеш"
  exit 1
fi

echo "[+] SPKI Hash: $HASH"

# Сборка нового stamp (с IP или без)
if [ -n "$IP" ]; then
  STAMP="sdns://Agc${HASH}"
else
  STAMP="sdns://Agc${HASH}"
fi

echo "[*] Обновляем dnsproxy.conf..."

# Заменяем строку stamp в конфиге
sed -i "s|^stamp = .*|stamp = '${STAMP}'|" "$CONF"

# Перезапускаем dnsproxy (если нужно)
pkill -f dnsproxy
"$BIN" "$CONF" &

echo "[✓] Обновление завершено!"
