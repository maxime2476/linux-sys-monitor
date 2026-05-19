#!/bin/bash

# ==============================================================================
# Script de surveillance système - Version 2.0 (Self-Healing)
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
    echo "Démarrage du service de surveillance avec auto-guérison..." >> "$SCRIPT_DIR/$LOG_FILE"
fi

while true; do
    DATE=$(date '+%Y-%m-%dT%H:%M:%S%z')

    # Extraction des données
    read RAM_TOTAL RAM_USED RAM_PERCENT <<< $(free -m | awk 'NR==2{printf "%s %s %.2f", $2, $3, $3*100/$2}')
    read DISK_TOTAL DISK_USED DISK_PERCENT <<< $(df -h / | awk 'NR==2{printf "%s %s %s", $2, $3, $5}' | sed 's/%//')
    read LOAD_1 LOAD_5 LOAD_15 <<< $(cat /proc/loadavg | awk '{print $1, $2, $3}')
    
    SSH_FAILED=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null)
    if [ -z "$SSH_FAILED" ]; then SSH_FAILED=0; fi

    # Logique d'Auto-Guérison (Self-Healing)
    HEALING_TRIGGERED="false"
    HEALING_SUCCESS="false"
    SERVICE_STATUS="unknown"
    
    if [ -n "$CRITICAL_SERVICE" ]; then
        SERVICE_STATUS=$(systemctl is-active "$CRITICAL_SERVICE" 2>/dev/null)
        
        if [ "$SERVICE_STATUS" != "active" ] && [ "$SERVICE_STATUS" != "unknown" ]; then
            HEALING_TRIGGERED="true"
            # Tentative de redémarrage (le script tourne en root désormais)
            systemctl restart "$CRITICAL_SERVICE"
            
            # Vérification post-redémarrage
            NEW_STATUS=$(systemctl is-active "$CRITICAL_SERVICE" 2>/dev/null)
            if [ "$NEW_STATUS" = "active" ]; then
                HEALING_SUCCESS="true"
                SERVICE_STATUS="recovered"
            else
                SERVICE_STATUS="failed"
            fi
        fi
    fi

    # Gestion des alertes
    ALERT_DISK="false"
    ALERT_SSH="false"
    
    if [ "$DISK_PERCENT" -gt "$DISK_THRESHOLD" ]; then ALERT_DISK="true"; fi
    if [ "$SSH_FAILED" -ge "$SSH_ALERT_THRESHOLD" ]; then ALERT_SSH="true"; fi

    # Notification Réseau (Webhook) - Mise à jour avec le Self-Healing
    if [ -n "$WEBHOOK_URL" ]; then
        MSG=""
        if [ "$ALERT_DISK" = "true" ] || [ "$ALERT_SSH" = "true" ]; then
            MSG="🚨 **ALERTE - Serveur: $(hostname)** 🚨\n- Disque: $ALERT_DISK\n- Brute-force: $ALERT_SSH"
        fi
        
        if [ "$HEALING_TRIGGERED" = "true" ]; then
            if [ "$HEALING_SUCCESS" = "true" ]; then
                MSG="$MSG\n🛠️ **AUTO-GUÉRISON :** Le service \`$CRITICAL_SERVICE\` a crashé mais a été redémarré avec succès par le script."
            else
                MSG="$MSG\n🔥 **ALERTE CRITIQUE :** Le service \`$CRITICAL_SERVICE\` a crashé et le redémarrage automatique a ÉCHOUÉ."
            fi
        fi

        if [ -n "$MSG" ]; then
            curl -s -X POST -H "Content-Type: application/json" -d "{\"content\": \"$MSG\"}" "$WEBHOOK_URL" > /dev/null
        fi
    fi

    # Format de sortie JSON
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        JSON_PAYLOAD=$(cat <<EOF
{
  "timestamp": "$DATE",
  "metrics": {
    "hardware": {
      "ram_used_mb": $RAM_USED,
      "ram_total_mb": $RAM_TOTAL,
      "disk_percent": $DISK_PERCENT,
      "cpu_load_1m": $LOAD_1
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
    "ssh_bruteforce": $ALERT_SSH
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
        echo "   Charge : $LOAD_1" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "   Sécurité: $SSH_FAILED tentatives SSH" >> "$SCRIPT_DIR/$LOG_FILE"
        if [ -n "$CRITICAL_SERVICE" ]; then
            echo "   Service ($CRITICAL_SERVICE) : $SERVICE_STATUS" >> "$SCRIPT_DIR/$LOG_FILE"
        fi
        echo "" >> "$SCRIPT_DIR/$LOG_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
