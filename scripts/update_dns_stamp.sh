#!/system/bin/sh

HOST=$(grep HOST "$MODDIR/dnsproxy.conf" | awk -F' = ' '{print $2}') 
IP=$(grep IP "$MODDIR/dnsproxy.conf" | awk -F' = ' '{print $2}') |          # Можно оставить пустым для stamp без IP
PORT="443"
PATH="/dns-query"

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
  STAMP="sdns://Agc${HASH}Dd3cuOTEuNjkuMTg0ABFoZWRpZ2Vob2cuZGRucy5uZXQKL2Rucy1xdWVyeQ"
else
  STAMP="sdns://Agc${HASH}ABFoZWRpZ2Vob2cuZGRucy5uZXQKL2Rucy1xdWVyeQ"
fi

echo "[*] Обновляем dnsproxy.conf..."

# Заменяем строку stamp в конфиге
sed -i "s|^stamp = .*|stamp = '${STAMP}'|" "$CONF"

# Перезапускаем dnsproxy (если нужно)
pkill -f dnsproxy
"$BIN" "$CONF" &

echo "[✓] Обновление завершено!"
