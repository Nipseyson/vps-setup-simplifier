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
done

# Открываем 80 и 443 для всех
ufw allow 80/tcp
ufw allow 443/tcp

ufw --force enable
echo "✅ UFW включён и настроен"

# 3. Настройка SSH-ключа
echo "🔐 Установка SSH-ключа..."

mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "$ssh_key" > ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 4. Конфигурируем sshd
echo "🔧 Обновление sshd_config..."

sshd_config="/etc/ssh/sshd_config"

sed -i "s/^#Port .*/Port $ssh_port/" "$sshd_config"
sed -i "s/^Port .*/Port $ssh_port/" "$sshd_config"

sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"

# Убедимся, что PermitRootLogin не стоит на yes
sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' "$sshd_config"
sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' "$sshd_config"

# Перезапуск ssh
echo "🔄 Перезапуск sshd..."
systemctl restart sshd

# 5. Крон-задача на ежедневную перезагрузку
echo "📅 Настройка cron-задачи на перезагрузку в 05:00 с задержкой до 10 минут..."

cron_line='0 5 * * * sleep $((RANDOM % 600)) && /sbin/reboot'

# Экранируем $ для crontab (иначе переменная подставится прямо сейчас)
escaped_cron_line='0 5 * * * sleep $((RANDOM \% 600)) && /sbin/reboot'

# Добавляем строку, избегая дублирования
(crontab -l 2>/dev/null | grep -v 'sleep.*reboot'; echo "$escaped_cron_line") | crontab -

echo -e "\n✅ Задача добавлена: reboot с задержкой до 10 минут в 05:00"

# Проверим, не существует ли уже такая задача
(crontab -l 2>/dev/null | grep -v '/sbin/reboot'; echo "$cron_line") | crontab -

echo -e "\n✅ Задача добавлена в crontab: ежедневная перезагрузка в 05:00"

# Финальное сообщение
echo -e "\n🎉 Готово! SSH работает на порту $ssh_port, вход разрешён только с IP:"
for ip in "${allowed_ips[@]}"; do
  echo "  ➤ $ip"
done

echo -e "\n⚠️ Убедись, что ты можешь подключиться по новому порту перед закрытием сессии."
