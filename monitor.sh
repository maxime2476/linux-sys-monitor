#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/monitor.conf"

[ -f "$CONFIG_FILE" ] || { echo "Config not found: $CONFIG_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

[ "$OUTPUT_FORMAT" != "json" ] && echo "Starting monitor..." >> "$SCRIPT_DIR/$LOG_FILE"

# FIM: compute baseline hashes at startup
declare -A FIM_BASELINE
if [ -n "$FIM_TARGETS" ]; then
    for f in $FIM_TARGETS; do
        [ -f "$f" ] && FIM_BASELINE["$f"]=$(sha256sum "$f" | awk '{print $1}')
    done
fi

OOM_BASELINE=$(dmesg 2>/dev/null | grep -c -i "Out of memory")
OOM_BASELINE=${OOM_BASELINE:-0}

LAST_ALERT=0

while true; do
    DATE=$(date '+%Y-%m-%dT%H:%M:%S%z')

    # Hardware metrics
    read -r RAM_TOTAL RAM_USED _ <<< "$(free -m | awk 'NR==2{printf "%s %s %.2f", $2, $3, $3*100/$2}')"
    read -r _ _ DISK_PERCENT <<< "$(df -h / | awk 'NR==2{printf "%s %s %s", $2, $3, $5}' | sed 's/%//')"
    read -r LOAD_1 _ _ < /proc/loadavg

    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        CPU_TEMP=$(( $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) / 1000 ))
    else
        CPU_TEMP=0
    fi

    # SSH brute-force
    SSH_FAILED=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null)
    SSH_FAILED=${SSH_FAILED:-0}

    # File integrity check
    ALERT_FIM="false"
    FIM_MODIFIED_FILES=""
    if [ -n "$FIM_TARGETS" ]; then
        for f in $FIM_TARGETS; do
            if [ -f "$f" ]; then
                curr=$(sha256sum "$f" | awk '{print $1}')
                if [ "${FIM_BASELINE["$f"]}" != "$curr" ]; then
                    ALERT_FIM="true"
                    FIM_MODIFIED_FILES="$FIM_MODIFIED_FILES $f"
                fi
            fi
        done
    fi
    FIM_MODIFIED_FILES=$(echo "$FIM_MODIFIED_FILES" | xargs)

    # SSL certificate expiry
    ALERT_SSL="false"
    SSL_EXPIRING_DOMAINS=""
    if [ -n "$SSL_DOMAINS" ]; then
        for domain in $SSL_DOMAINS; do
            exp=$(echo | timeout 5 openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null \
                | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
            if [ -n "$exp" ]; then
                exp_sec=$(date -d "$exp" +%s 2>/dev/null)
                now_sec=$(date +%s)
                if [ -n "$exp_sec" ]; then
                    days=$(( (exp_sec - now_sec) / 86400 ))
                    if [ "$days" -le "$SSL_DAYS_THRESHOLD" ]; then
                        ALERT_SSL="true"
                        SSL_EXPIRING_DOMAINS="$SSL_EXPIRING_DOMAINS $domain(${days}j)"
                    fi
                fi
            fi
        done
    fi
    SSL_EXPIRING_DOMAINS=$(echo "$SSL_EXPIRING_DOMAINS" | xargs)

    # Docker container health
    ALERT_DOCKER="false"
    DOCKER_CRASHED=""
    if [ "$CHECK_DOCKER" = "true" ] && command -v docker >/dev/null 2>&1; then
        DOCKER_CRASHED=$(docker ps --filter "status=exited" --filter "status=dead" --format "{{.Names}}" 2>/dev/null | xargs)
        [ -n "$DOCKER_CRASHED" ] && ALERT_DOCKER="true"
    fi

    # OOM-killer events (delta since start)
    ALERT_OOM="false"
    OOM_CURRENT=$(dmesg 2>/dev/null | grep -c -i "Out of memory")
    OOM_CURRENT=${OOM_CURRENT:-0}
    if [ "$OOM_CURRENT" -gt "$OOM_BASELINE" ]; then
        ALERT_OOM="true"
        OOM_BASELINE=$OOM_CURRENT
    fi

    # Network health
    if [ -n "$PING_TARGET" ]; then
        PACKET_LOSS=$(ping -c 3 -W 2 "$PING_TARGET" 2>/dev/null | grep -o '[0-9]*% packet loss' | awk -F'%' '{print $1}')
        PACKET_LOSS=${PACKET_LOSS:-100}
    else
        PACKET_LOSS=0
    fi

    # Service self-healing (systemd / bare-metal only)
    # Note: systemctl returns empty string in Docker (no systemd PID 1); we treat that as "unknown"
    # to avoid false positives — the healing logic is only meaningful on systemd-managed hosts.
    HEALING_TRIGGERED="false"
    HEALING_SUCCESS="false"
    SERVICE_STATUS="unknown"
    if [ -n "$CRITICAL_SERVICE" ]; then
        SERVICE_STATUS=$(systemctl is-active "$CRITICAL_SERVICE" 2>/dev/null)
        [ -z "$SERVICE_STATUS" ] && SERVICE_STATUS="unknown"

        if [ "$SERVICE_STATUS" != "active" ] && [ "$SERVICE_STATUS" != "unknown" ]; then
            HEALING_TRIGGERED="true"
            systemctl restart "$CRITICAL_SERVICE" 2>/dev/null
            SERVICE_STATUS=$(systemctl is-active "$CRITICAL_SERVICE" 2>/dev/null)
            [ -z "$SERVICE_STATUS" ] && SERVICE_STATUS="unknown"
            if [ "$SERVICE_STATUS" = "active" ]; then
                HEALING_SUCCESS="true"
                SERVICE_STATUS="recovered"
            else
                SERVICE_STATUS="failed"
            fi
        fi
    fi

    # Threshold breach flags
    ALERT_DISK="false"
    ALERT_SSH="false"
    ALERT_TEMP="false"
    ALERT_NET="false"
    [ "$DISK_PERCENT" -gt "$DISK_THRESHOLD" ] && ALERT_DISK="true"
    [ "$SSH_FAILED" -ge "$SSH_ALERT_THRESHOLD" ] && ALERT_SSH="true"
    [ "$CPU_TEMP" -gt 0 ] && [ "$CPU_TEMP" -ge "$TEMP_THRESHOLD" ] && ALERT_TEMP="true"
    [ "$PACKET_LOSS" -ge "$MAX_PACKET_LOSS" ] && ALERT_NET="true"

    # Webhook notifications — throttled to at most one alert every 5 minutes
    if [ -n "$WEBHOOK_URL" ]; then
        MSG=""
        if [ "$ALERT_DISK" = "true" ] || [ "$ALERT_SSH" = "true" ] || [ "$ALERT_TEMP" = "true" ] || [ "$ALERT_NET" = "true" ]; then
            MSG="🚨 **ALERTE - Serveur: $(hostname)** 🚨\n- Disque: $ALERT_DISK\n- Brute-force: $ALERT_SSH\n- CPU: $ALERT_TEMP\n- Réseau: $ALERT_NET"
        fi
        [ "$ALERT_FIM" = "true" ] && MSG="$MSG\n☠️ **FIM :** Fichier modifié : \`$FIM_MODIFIED_FILES\`"
        [ "$ALERT_OOM" = "true" ] && MSG="$MSG\n💀 **OOM :** Saturation RAM, processus abattu."
        [ "$ALERT_SSL" = "true" ] && MSG="$MSG\n🔐 **SSL :** Certificat(s) expirant bientôt : \`$SSL_EXPIRING_DOMAINS\`"
        [ "$ALERT_DOCKER" = "true" ] && MSG="$MSG\n🐳 **DOCKER :** Conteneur(s) crashé(s) : \`$DOCKER_CRASHED\`"
        if [ "$HEALING_TRIGGERED" = "true" ]; then
            if [ "$HEALING_SUCCESS" = "true" ]; then
                MSG="$MSG\n🛠️ **AUTO-GUÉRISON :** Le service \`$CRITICAL_SERVICE\` a été redémarré."
            else
                MSG="$MSG\n🔥 **CRITIQUE :** Le service \`$CRITICAL_SERVICE\` a crashé."
            fi
        fi

        if [ -n "$MSG" ]; then
            now=$(date +%s)
            if [ $((now - LAST_ALERT)) -gt 300 ]; then
                curl -s -X POST -H "Content-Type: application/json" \
                    -d "{\"content\": \"$MSG\"}" "$WEBHOOK_URL" > /dev/null
                LAST_ALERT=$now
            fi
        fi
    fi

    # Write metrics atomically
    JSON_PAYLOAD=$(cat <<EOF
{
  "timestamp": "$DATE",
  "metrics": {
    "hardware": {
      "ram_used_mb": $RAM_USED,
      "ram_total_mb": $RAM_TOTAL,
      "disk_percent": $DISK_PERCENT,
      "cpu_load_1m": $LOAD_1,
      "cpu_temp_c": $CPU_TEMP
    },
    "network": {
      "target": "$PING_TARGET",
      "packet_loss_percent": $PACKET_LOSS
    },
    "security": {
      "ssh_failed_attempts": $SSH_FAILED,
      "fim_alert": $ALERT_FIM,
      "fim_modified_files": "$FIM_MODIFIED_FILES",
      "ssl_alert": $ALERT_SSL,
      "ssl_expiring": "$SSL_EXPIRING_DOMAINS"
    },
    "kernel": {
      "oom_killer_events": $OOM_CURRENT,
      "oom_alert": $ALERT_OOM
    },
    "docker": {
      "crashed_containers": "$DOCKER_CRASHED"
    },
    "services": {
      "target": "$CRITICAL_SERVICE",
      "status": "$SERVICE_STATUS",
      "healing_triggered": $HEALING_TRIGGERED,
      "healing_success": $HEALING_SUCCESS
    }
  },
  "alerts": {
    "disk_critical": $ALERT_DISK,
    "ssh_bruteforce": $ALERT_SSH,
    "cpu_overheat": $ALERT_TEMP,
    "network_degraded": $ALERT_NET,
    "file_integrity_compromised": $ALERT_FIM,
    "kernel_oom_triggered": $ALERT_OOM,
    "ssl_certificate_expiring": $ALERT_SSL,
    "docker_container_crashed": $ALERT_DOCKER
  }
}
EOF
)

    echo "$JSON_PAYLOAD" > "$SCRIPT_DIR/metrics.tmp"
    mv "$SCRIPT_DIR/metrics.tmp" "$SCRIPT_DIR/metrics.json"

    if [ "$ENABLE_WEB_SERVER" = "true" ]; then
        if ! pgrep -f "python3 -m http.server $WEB_PORT" > /dev/null; then
            cd "$SCRIPT_DIR" && nohup python3 -m http.server "$WEB_PORT" > /dev/null 2>&1 &
        fi
    fi

    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "$JSON_PAYLOAD" >> "$SCRIPT_DIR/$LOG_FILE"
    else
        echo "---" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "[$DATE] RAM:${RAM_USED}MB disk:${DISK_PERCENT}% load:${LOAD_1}" >> "$SCRIPT_DIR/$LOG_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
