#!/bin/bash

# ==============================================================================
# Script de surveillance système - Version 1.6 (Audit de sécurité SSH)
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

    # Extraction des données matérielles
    read RAM_TOTAL RAM_USED RAM_PERCENT <<< $(free -m | awk 'NR==2{printf "%s %s %.2f", $2, $3, $3*100/$2}')
    read DISK_TOTAL DISK_USED DISK_PERCENT <<< $(df -h / | awk 'NR==2{printf "%s %s %s", $2, $3, $5}' | sed 's/%//')
    read LOAD_1 LOAD_5 LOAD_15 <<< $(cat /proc/loadavg | awk '{print $1, $2, $3}')

    # Extraction des données de sécurité (comptage des échecs SSH)
    SSH_FAILED=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null)
    # Si la variable est vide (fichier inexistant ou sans droits), on force à 0
    if [ -z "$SSH_FAILED" ]; then SSH_FAILED=0; fi

    # Gestion des alertes
    ALERT_DISK="false"
    ALERT_SSH="false"
    
    if [ "$DISK_PERCENT" -gt "$DISK_THRESHOLD" ]; then
        ALERT_DISK="true"
    fi
    if [ "$SSH_FAILED" -ge "$SSH_ALERT_THRESHOLD" ]; then
        ALERT_SSH="true"
    fi

    # Format de sortie
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
        echo "   Sécurité: $SSH_FAILED tentatives SSH échouées" >> "$SCRIPT_DIR/$LOG_FILE"
        
        if [ "$ALERT_DISK" = "true" ]; then echo "   [ALERTE] /!\ Espace disque critique" >> "$SCRIPT_DIR/$LOG_FILE"; fi
        if [ "$ALERT_SSH" = "true" ];  then echo "   [ALERTE] /!\ Attaque brute-force SSH détectée" >> "$SCRIPT_DIR/$LOG_FILE"; fi
        echo "" >> "$SCRIPT_DIR/$LOG_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
