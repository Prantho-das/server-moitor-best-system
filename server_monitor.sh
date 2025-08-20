#!/bin/bash

CONFIG_FILE="$HOME/.server_monitor_config"
CRON_FILE="$HOME/.server_monitor_cron"
TOKEN_FILE="$HOME/.server_monitor_token"   # Bearer token

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

# ------------------ Server URL ------------------
ask_server() {
    if [ -f "$CONFIG_FILE" ]; then
        SERVER_URL=$(cat "$CONFIG_FILE")
    else
        read -p "Enter external server URL to send reports: " SERVER_URL
        echo "$SERVER_URL" > "$CONFIG_FILE"
        echo "Server URL saved. Edit $CONFIG_FILE to change."
    fi
}

update_server() {
    read -p "Change server URL? (y/n): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        read -p "Enter new server URL: " SERVER_URL
        echo "$SERVER_URL" > "$CONFIG_FILE"
        echo "Server URL updated."
    fi
}

ask_server
update_server

# ------------------ Bearer Token ------------------
ask_token() {
    if [ -f "$TOKEN_FILE" ]; then
        TOKEN=$(cat "$TOKEN_FILE")
    else
        read -p "Enter your Bearer token: " TOKEN
        echo "$TOKEN" > "$TOKEN_FILE"
        echo "Token saved. Edit $TOKEN_FILE to change."
    fi
}

ask_token

# ------------------ Helpers ------------------
service_usage() {
    local svc=$1
    local status mem cpu
    if pgrep -x "$svc" >/dev/null 2>&1; then
        status="running"
        mem=$(ps -C "$svc" -o rss= | awk '{sum+=$1} END{printf "%.2f", sum/1024}')
        cpu=$(ps -C "$svc" -o %cpu= | awk '{sum+=$1} END{printf "%.2f", sum}')
    else
        status="stopped"
        mem=0
        cpu=0
    fi
    echo "{\"status\":\"$status\",\"mem_mb\":$mem,\"cpu_percent\":$cpu}"
}

# ------------------ System Info ------------------
HOSTNAME=$(hostname)
OS="$(uname -s) $(uname -r)"
UPTIME=$(uptime -p)
CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
CPU_CORES=$(nproc)
MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEM_USED=$(free -m | awk 'NR==2{print $3}')
MEM_PERCENT=$(( MEM_USED*100/MEM_TOTAL ))
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
DISK_USED=$(df -h / | awk 'NR==2{print $3}')
DISK_PERCENT=$(df / | awk 'NR==2{print $5}' | sed 's/%//')
LOAD_AVG=$(awk '{print $1,$2,$3}' /proc/loadavg)
PUBLIC_IP=$(curl -s https://api.ipify.org || echo "N/A")

# ------------------ Services ------------------
NGINX=$(service_usage nginx)
PHPFPM=$(service_usage php-fpm)
MYSQL=$(service_usage mysqld)
SUPERVISOR=$(service_usage supervisor)
CRON=$(service_usage cron)
REDIS=$(service_usage redis-server)

# ------------------ PHP Modules Status ------------------
PHP_MODULES_JSON="{"
if command -v php >/dev/null 2>&1; then
    MODULES=$(php -m 2>/dev/null)
    for mod in $MODULES; do
        php -r "extension_loaded('$mod') || exit 1;" 2>/dev/null
        if [ $? -eq 0 ]; then
            status="enabled"
        else
            status="disabled"
        fi
        PHP_MODULES_JSON+="\"$mod\":\"$status\","
    done
    PHP_MODULES_JSON="${PHP_MODULES_JSON%,}"
else
    PHP_MODULES_JSON+="\"error\":\"php not installed\""
fi
PHP_MODULES_JSON+="}"

# ------------------ PM2 Processes ------------------
PM2_JSON="[]"
if command -v pm2 >/dev/null 2>&1; then
    PM2_PROCS=$(pm2 jlist 2>/dev/null)
    if [ -n "$PM2_PROCS" ]; then
        PM2_JSON=$(echo "$PM2_PROCS" | node -e "
            const proc = JSON.parse(require('fs').readFileSync(0,'utf-8'));
            console.log(JSON.stringify(proc.map(p=>({
                name:p.name,
                status:p.pm2_env.status,
                cpu_percent:p.monit.cpu,
                mem_mb:(p.monit.memory/1024/1024).toFixed(2)
            }))));
        ")
    fi
fi

# ------------------ Docker Containers ------------------
DOCKER_JSON="[]"
if command -v docker >/dev/null 2>&1; then
    DOCKER_STATS=$(docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.Status}}')
    if [ -n "$DOCKER_STATS" ]; then
        DOCKER_JSON="["
        while IFS='|' read -r name cpu mem status; do
            cpu_clean=$(echo $cpu | tr -d '%')
            mem_val=$(echo $mem | awk '{print $1}')
            DOCKER_JSON+="{\"name\":\"$name\",\"cpu_percent\":${cpu_clean:-0},\"mem\":\"$mem_val\",\"status\":\"$status\"},"
        done <<< "$DOCKER_STATS"
        DOCKER_JSON="${DOCKER_JSON%,}]"
    fi
fi

# ------------------ Compose JSON ------------------
REPORT=$(cat <<EOF
{
  "hostname":"$HOSTNAME",
  "public_ip":"$PUBLIC_IP",
  "os":"$OS",
  "uptime":"$UPTIME",
  "cpu_load":"$CPU_LOAD",
  "cpu_cores":$CPU_CORES,
  "memory_total_mb":$MEM_TOTAL,
  "memory_used_mb":$MEM_USED,
  "memory_percent":$MEM_PERCENT,
  "disk_total":"$DISK_TOTAL",
  "disk_used":"$DISK_USED",
  "disk_percent":$DISK_PERCENT,
  "load_avg":"$LOAD_AVG",
  "nginx":$NGINX,
  "php_fpm":$PHPFPM,
  "php_modules":$PHP_MODULES_JSON,
  "mysql":$MYSQL,
  "supervisor":$SUPERVISOR,
  "cron":$CRON,
  "redis":$REDIS,
  "pm2_processes":$PM2_JSON,
  "docker_containers":$DOCKER_JSON
}
EOF
)

# ------------------ Send JSON ------------------
if command -v curl >/dev/null 2>&1; then
    RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d "$REPORT" "$SERVER_URL")
    echo -e "${CYAN}Server response:${RESET}\n$RESPONSE"
else
    echo -e "${RED}curl not installed. Cannot send report.${RESET}"
fi

# ------------------ Cron Setup ------------------
if [ ! -f "$CRON_FILE" ]; then
    (crontab -l 2>/dev/null; echo "*/5 * * * * $PWD/$(basename $0)") | crontab -
    touch "$CRON_FILE"
    echo -e "${GREEN}Cron job added to run script every 5 minutes${RESET}"
fi

# ------------------ Terminal Summary ------------------
echo -e "${CYAN}==============================="
echo -e "     DevOps Health Check Done"
echo -e "===============================${RESET}"
echo -e "CPU Load: $CPU_LOAD% | Mem Usage: $MEM_PERCENT% | Disk Usage: $DISK_PERCENT%"
echo -e "Public IP: $PUBLIC_IP"
