#!/bin/bash

set -e

HAPROXY_CFG="/etc/haproxy/haproxy.cfg"

# Проверка прав
if [[ $EUID -ne 0 ]]; then
  echo "❌ Скрипт нужно запускать от root" >&2
  exit 1
fi

# Ввод нового домена
read -p "➡️ Введите новый маскировочный SNI-домен: " new_sni
[[ -z "$new_sni" ]] && { echo "❌ Домен не может быть пустым"; exit 1; }

# Определим текущий домен (по backend reality)
old_sni=$(grep -oP 'use_backend reality if \{ req\.ssl_sni -i end +\K\S+' "$HAPROXY_CFG" | head -n1)

if [[ -z "$old_sni" ]]; then
  echo "⚠️ Не найден текущий маскировочный домен в $HAPROXY_CFG"
  exit 1
fi

echo "🔁 Заменяем: $old_sni → $new_sni"

# Обновим файл
sed -i "s/$old_sni/$new_sni/g" "$HAPROXY_CFG"
echo "✅ Обновлён конфиг HAProxy: $HAPROXY_CFG"

# Перезапуск
systemctl restart haproxy
echo "✅ HAProxy перезапущен"

# Финал
echo -e "\n🎉 Маскировочный домен успешно обновлён!"
