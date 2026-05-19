#!/bin/bash

# ==============================================================================
# Script de surveillance système - Version 2.2 (Connectivité Réseau)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/monitor.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERREUR FATALE : Le fichier de configuration $CONFIG_FILE est introuvable."
    exit 1
fi

if [ "$OUTPUT_FORMAT" != "json" ]; then
    echo "Démarrage du service de surveillance..." >> "$SCRIPT_DIR/$LOG_FILE"
fi

while true; do
    DATE=$(date '+%Y-%m-%dT%H:%M:%S%z')

    # 1. Données Matérielles
    read RAM_TOTAL RAM_USED RAM_PERCENT <<< $(free -m | awk 'NR==2{printf "%s %s %.2f", $2, $3, $3*100/$2}')
    read DISK_TOTAL DISK_USED DISK_PERCENT <<< $(df -h / | awk 'NR==2{printf "%s %s %s", $2, $3, $5}' | sed 's/%//')
    read LOAD_1 LOAD_5 LOAD_15 <<< $(cat /proc/loadavg | awk '{print $1, $2, $3}')
    
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        CPU_TEMP=$(( $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) / 1000 ))
    else
        CPU_TEMP=0
    fi

    # 2. Données de Sécurité
    SSH_FAILED=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null)
    if [ -z "$SSH_FAILED" ]; then SSH_FAILED=0; fi

    # 3. Connectivité Réseau
    if [ -n "$PING_TARGET" ]; then
        PACKET_LOSS=$(ping -c 3 -W 2 "$PING_TARGET" 2>/dev/null | grep -o '[0-9]*% packet loss' | awk -F'%' '{print $1}')
        if [ -z "$PACKET_LOSS" ]; then PACKET_LOSS=100; fi
    else
        PACKET_LOSS=0
    fi

    # 4. Logique d'Auto-Guérison
    HEALING_TRIGGERED="false"
    HEALING_SUCCESS="false"
    SERVICE_STATUS="unknown"
    
    if [ -n "$CRITICAL_SERVICE" ]; then
        SERVICE_STATUS=$(systemctl is-active "$CRITICAL_SERVICE" 2>/dev/null)
        if [ "$SERVICE_STATUS" != "active" ] && [ "$SERVICE_STATUS" != "unknown" ]; then
            HEALING_TRIGGERED="true"
            systemctl restart "$CRITICAL_SERVICE"
            NEW_STATUS=$(systemctl is-active "$CRITICAL_SERVICE" 2>/dev/null)
            if [ "$NEW_STATUS" = "active" ]; then
                HEALING_SUCCESS="true"
                SERVICE_STATUS="recovered"
            else
                SERVICE_STATUS="failed"
            fi
        fi
    fi

    # 5. Gestion des alertes
    ALERT_DISK="false"
    ALERT_SSH="false"
    ALERT_TEMP="false"
    ALERT_NET="false"
    
    if [ "$DISK_PERCENT" -gt "$DISK_THRESHOLD" ]; then ALERT_DISK="true"; fi
    if [ "$SSH_FAILED" -ge "$SSH_ALERT_THRESHOLD" ]; then ALERT_SSH="true"; fi
    if [ "$CPU_TEMP" -gt 0 ] && [ "$CPU_TEMP" -ge "$TEMP_THRESHOLD" ]; then ALERT_TEMP="true"; fi
    if [ "$PACKET_LOSS" -ge "$MAX_PACKET_LOSS" ]; then ALERT_NET="true"; fi

    # 6. Notification Réseau (Webhook)
    if [ -n "$WEBHOOK_URL" ]; then
        MSG=""
        if [ "$ALERT_DISK" = "true" ] || [ "$ALERT_SSH" = "true" ] || [ "$ALERT_TEMP" = "true" ] || [ "$ALERT_NET" = "true" ]; then
            MSG="🚨 **ALERTE - Serveur: $(hostname)** 🚨\n- Disque: $ALERT_DISK\n- Brute-force: $ALERT_SSH\n- Surchauffe CPU: $ALERT_TEMP\n- Réseau Dégradé: $ALERT_NET ($PACKET_LOSS% de perte)"
        fi
        
        if [ "$HEALING_TRIGGERED" = "true" ]; then
            if [ "$HEALING_SUCCESS" = "true" ]; then
                MSG="$MSG\n🛠️ **AUTO-GUÉRISON :** Le service \`$CRITICAL_SERVICE\` a été redémarré avec succès."
            else
                MSG="$MSG\n🔥 **ALERTE CRITIQUE :** Le service \`$CRITICAL_SERVICE\` a crashé (Redémarrage ÉCHOUÉ)."
            fi
        fi

        if [ -n "$MSG" ]; then
            curl -s -X POST -H "Content-Type: application/json" -d "{\"content\": \"$MSG\"}" "$WEBHOOK_URL" > /dev/null
        fi
    fi

    # 7. Format de sortie JSON
    if [ "$OUTPUT_FORMAT" = "json" ]; then
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
      "ssh_failed_attempts": $SSH_FAILED
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
    "network_degraded": $ALERT_NET
  }
}
EOF
)
        echo "$JSON_PAYLOAD" >> "$SCRIPT_DIR/$LOG_FILE"
    else
        # Sortie Texte
        echo "---------------------------------------------------" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "Rapport de santé du système - $DATE" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "   RAM    : $RAM_USED MB / $RAM_TOTAL MB" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "   Disque : $DISK_PERCENT%" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "   Temp CPU: $CPU_TEMP °C" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "   Réseau : $PACKET_LOSS% de perte vers $PING_TARGET" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "" >> "$SCRIPT_DIR/$LOG_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
