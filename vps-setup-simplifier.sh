#!/bin/bash

# Проверка прав
if [[ $EUID -ne 0 ]]; then
  echo "❌ Скрипт нужно запускать от root" >&2
  exit 1
fi

echo "🛠 Настройка SSH и фаервола"

# 1. Ввод параметров
read -p "➡️  Введите порт для SSH: " ssh_port
read -p "➡️  Введите ваш публичный SSH-ключ (одной строкой): " ssh_key
read -p "➡️  Разрешённые IP-адреса (через запятую) для SSH и VPN панели: " allowed_ips_raw

# Парсим IP
IFS=',' read -ra allowed_ips <<< "$allowed_ips_raw"

# 2. Настройка UFW
echo "⚙️ Настройка фаервола (UFW)..."

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Разрешённые IP
for ip in "${allowed_ips[@]}"; do
  ufw allow from "$ip" to any port "$ssh_port" proto tcp
  ufw allow from "$ip" to any port 8443 proto tcp
done

# Открываем 80 и 443 для всех
ufw allow 80/tcp
ufw allow 443/tcp

ufw --force enable
echo "✅ UFW включён и настроен"

# 3. Настройка SSH-ключа
echo "🔐 Установка SSH-ключа в /root/.ssh..."

mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "$ssh_key" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "✅ Ключ установлен для пользователя root"

# 4. Конфигурируем sshd
echo "🔧 Обновление sshd_config..."

sshd_config="/etc/ssh/sshd_config"

# Установка порта
if grep -q "^#\?Port " "$sshd_config"; then
  sed -i "s/^#\?Port .*/Port $ssh_port/" "$sshd_config"
else
  echo "Port $ssh_port" >> "$sshd_config"
fi

# Отключение пароля
if grep -q "^#\?PasswordAuthentication " "$sshd_config"; then
  sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' "$sshd_config"
else
  echo "PasswordAuthentication no" >> "$sshd_config"
fi

# PermitRootLogin (против "yes")
if grep -q "^#\?PermitRootLogin " "$sshd_config"; then
  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' "$sshd_config"
else
  echo "PermitRootLogin prohibit-password" >> "$sshd_config"
fi

# Перезапуск ssh
echo "🔄 Перезапуск sshd..."
if systemctl list-units --type=service | grep -q sshd.service; then
  systemctl restart sshd
elif systemctl list-units --type=service | grep -q ssh.service; then
  systemctl restart ssh
else
  echo "⚠️ Не удалось найти службу SSH (sshd/ssh), перезапуск не выполнен"
fi


# 5. Крон-задача на ежедневную перезагрузку
echo "📅 Настройка cron-задачи на перезагрузку в 05:00 с задержкой до 10 минут..."

escaped_cron_line='0 5 * * * sleep $((RANDOM \% 600)) && /sbin/reboot'

# Удаляем старые задачи с reboot, если были, и добавляем новую
(crontab -l 2>/dev/null | grep -v '/sbin/reboot'; echo "$escaped_cron_line") | crontab -

echo "✅ Cron задача добавлена"

# 6. Отключение IPv6 по запросу
read -rp "❓ Отключить IPv6? [y/N]: " disable_ipv6
disable_ipv6=${disable_ipv6,,} # в нижний регистр

if [[ "$disable_ipv6" == "y" || "$disable_ipv6" == "yes" ]]; then
    echo "🚫 Отключаем IPv6..."

    cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    sysctl --system > /dev/null
    echo "✅ IPv6 отключён"
else
    echo "ℹ️ IPv6 оставлен включённым"
fi

# Финальное сообщение
echo -e "\n🎉 Готово! SSH работает на порту $ssh_port, вход разрешён только с IP:"
for ip in "${allowed_ips[@]}"; do
  echo "  ➤ $ip"
done

echo -e "\n⚠️ Убедись, что ты можешь подключиться по новому порту перед закрытием сессии."
