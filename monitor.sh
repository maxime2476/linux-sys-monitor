#!/bin/bash

# ==============================================================================
# Script de surveillance système - Version 5.0 (OOM-Killer & Post-Mortem)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/monitor.conf"

if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; else exit 1; fi

if [ "$OUTPUT_FORMAT" != "json" ]; then
    echo "Démarrage du service de surveillance..." >> "$SCRIPT_DIR/$LOG_FILE"
fi

# ==============================================================================
# INITIALISATION
# ==============================================================================

# 1. Baseline FIM
declare -A FIM_BASELINE
if [ -n "$FIM_TARGETS" ]; then
    for FILE in $FIM_TARGETS; do
        if [ -f "$FILE" ]; then FIM_BASELINE["$FILE"]=$(sha256sum "$FILE" | awk '{print $1}'); fi
    done
fi

# 2. Baseline OOM-Killer (Comptage des événements historiques du noyau)
OOM_BASELINE=$(dmesg 2>/dev/null | grep -c -i "Out of memory")
if [ -z "$OOM_BASELINE" ]; then OOM_BASELINE=0; fi

# ==============================================================================
# BOUCLE PRINCIPALE
# ==============================================================================

while true; do
    DATE=$(date '+%Y-%m-%dT%H:%M:%S%z')

    # 1. Matériel
    read RAM_TOTAL RAM_USED RAM_PERCENT <<< $(free -m | awk 'NR==2{printf "%s %s %.2f", $2, $3, $3*100/$2}')
    read DISK_TOTAL DISK_USED DISK_PERCENT <<< $(df -h / | awk 'NR==2{printf "%s %s %s", $2, $3, $5}' | sed 's/%//')
    read LOAD_1 LOAD_5 LOAD_15 <<< $(cat /proc/loadavg | awk '{print $1, $2, $3}')
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then CPU_TEMP=$(( $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) / 1000 )); else CPU_TEMP=0; fi

    # 2. Sécurité : Bruteforce SSH
    SSH_FAILED=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null)
    if [ -z "$SSH_FAILED" ]; then SSH_FAILED=0; fi

    # 3. Sécurité : FIM
    ALERT_FIM="false"
    FIM_MODIFIED_FILES=""
    if [ -n "$FIM_TARGETS" ]; then
        for FILE in $FIM_TARGETS; do
            if [ -f "$FILE" ]; then
                CURRENT_HASH=$(sha256sum "$FILE" | awk '{print $1}')
                if [ "${FIM_BASELINE["$FILE"]}" != "$CURRENT_HASH" ]; then
                    ALERT_FIM="true"
                    FIM_MODIFIED_FILES="$FIM_MODIFIED_FILES $FILE"
                fi
            fi
        done
    fi
    FIM_MODIFIED_FILES=$(echo "$FIM_MODIFIED_FILES" | xargs)

    # 4. Analyse Post-Mortem du Noyau (OOM-Killer)
    ALERT_OOM="false"
    OOM_CURRENT=$(dmesg 2>/dev/null | grep -c -i "Out of memory")
    if [ -z "$OOM_CURRENT" ]; then OOM_CURRENT=0; fi
    
    if [ "$OOM_CURRENT" -gt "$OOM_BASELINE" ]; then
        ALERT_OOM="true"
        # Mise à jour de la baseline pour ne pas spammer les alertes au prochain cycle
        OOM_BASELINE=$OOM_CURRENT
    fi

    # 5. Réseau
    if [ -n "$PING_TARGET" ]; then
        PACKET_LOSS=$(ping -c 3 -W 2 "$PING_TARGET" 2>/dev/null | grep -o '[0-9]*% packet loss' | awk -F'%' '{print $1}')
        if [ -z "$PACKET_LOSS" ]; then PACKET_LOSS=100; fi
    else
        PACKET_LOSS=0
    fi

    # 6. Auto-Guérison
    HEALING_TRIGGERED="false"
    HEALING_SUCCESS="false"
    SERVICE_STATUS="unknown"
    if [ -n "$CRITICAL_SERVICE" ]; then
        SERVICE_STATUS=$(systemctl is-active "$CRITICAL_SERVICE" 2>/dev/null)
        if [ "$SERVICE_STATUS" != "active" ] && [ "$SERVICE_STATUS" != "unknown" ]; then
            HEALING_TRIGGERED="true"
            systemctl restart "$CRITICAL_SERVICE"
            NEW_STATUS=$(systemctl is-active "$CRITICAL_SERVICE" 2>/dev/null)
            if [ "$NEW_STATUS" = "active" ]; then HEALING_SUCCESS="true"; SERVICE_STATUS="recovered"
            else SERVICE_STATUS="failed"; fi
        fi
    fi

    # 7. Alertes de base
    ALERT_DISK="false"; ALERT_SSH="false"; ALERT_TEMP="false"; ALERT_NET="false"
    if [ "$DISK_PERCENT" -gt "$DISK_THRESHOLD" ]; then ALERT_DISK="true"; fi
    if [ "$SSH_FAILED" -ge "$SSH_ALERT_THRESHOLD" ]; then ALERT_SSH="true"; fi
    if [ "$CPU_TEMP" -gt 0 ] && [ "$CPU_TEMP" -ge "$TEMP_THRESHOLD" ]; then ALERT_TEMP="true"; fi
    if [ "$PACKET_LOSS" -ge "$MAX_PACKET_LOSS" ]; then ALERT_NET="true"; fi

    # 8. Webhook
    if [ -n "$WEBHOOK_URL" ]; then
        MSG=""
        if [ "$ALERT_DISK" = "true" ] || [ "$ALERT_SSH" = "true" ] || [ "$ALERT_TEMP" = "true" ] || [ "$ALERT_NET" = "true" ]; then
            MSG="🚨 **ALERTE - Serveur: $(hostname)** 🚨\n- Disque: $ALERT_DISK\n- Brute-force: $ALERT_SSH\n- CPU: $ALERT_TEMP\n- Réseau: $ALERT_NET"
        fi
        
        if [ "$ALERT_FIM" = "true" ]; then MSG="$MSG\n☠️ **VIOLATION D'INTÉGRITÉ :** Fichier modifié : \`$FIM_MODIFIED_FILES\`"; fi
        
        if [ "$ALERT_OOM" = "true" ]; then MSG="$MSG\n💀 **FATAL KERNEL OOM :** La RAM a saturé et le noyau Linux a abattu un processus."; fi

        if [ "$HEALING_TRIGGERED" = "true" ]; then
            if [ "$HEALING_SUCCESS" = "true" ]; then MSG="$MSG\n🛠️ **AUTO-GUÉRISON :** Le service \`$CRITICAL_SERVICE\` a été redémarré."; else MSG="$MSG\n🔥 **CRITIQUE :** Le service \`$CRITICAL_SERVICE\` a crashé."; fi
        fi

        if [ -n "$MSG" ]; then curl -s -X POST -H "Content-Type: application/json" -d "{\"content\": \"$MSG\"}" "$WEBHOOK_URL" > /dev/null; fi
    fi

    # 9. JSON Payload
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
      "fim_modified_files": "$FIM_MODIFIED_FILES"
    },
    "kernel": {
      "oom_killer_events": $OOM_CURRENT,
      "oom_alert": $ALERT_OOM
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
    "kernel_oom_triggered": $ALERT_OOM
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
        echo "---------------------------------------------------" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "Rapport - $DATE | RAM:$RAM_USED MB | OOM_ALERT:$ALERT_OOM" >> "$SCRIPT_DIR/$LOG_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
