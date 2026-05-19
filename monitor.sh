#!/bin/bash

# ==============================================================================
# Script de surveillance système - Version 1.5 (Support JSON)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/monitor.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERREUR FATALE : Le fichier de configuration $CONFIG_FILE est introuvable."
    exit 1
fi

# Initialisation du log en texte uniquement
if [ "$OUTPUT_FORMAT" != "json" ]; then
    echo "Démarrage du service de surveillance..." >> "$SCRIPT_DIR/$LOG_FILE"
fi

while true; do
    # Formatage ISO 8601 pour la date (standard attendu dans les fichiers JSON)
    DATE=$(date '+%Y-%m-%dT%H:%M:%S%z')

    # Extraction des données brutes dans des variables
    read RAM_TOTAL RAM_USED RAM_PERCENT <<< $(free -m | awk 'NR==2{printf "%s %s %.2f", $2, $3, $3*100/$2}')
    read DISK_TOTAL DISK_USED DISK_PERCENT <<< $(df -h / | awk 'NR==2{printf "%s %s %s", $2, $3, $5}' | sed 's/%//')
    read LOAD_1 LOAD_5 LOAD_15 <<< $(cat /proc/loadavg | awk '{print $1, $2, $3}')

    # Gestion de l'alerte
    ALERT_STATUS="false"
    if [ "$DISK_PERCENT" -gt "$DISK_THRESHOLD" ]; then
        ALERT_STATUS="true"
    fi

    # Condition d'affichage selon le format choisi
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        # Construction du bloc JSON strict
        JSON_PAYLOAD=$(cat <<EOF
{
  "timestamp": "$DATE",
  "metrics": {
    "ram": {
      "total_mb": $RAM_TOTAL,
      "used_mb": $RAM_USED,
      "percent": $RAM_PERCENT
    },
    "disk": {
      "total": "$DISK_TOTAL",
      "used": "$DISK_USED",
      "percent": $DISK_PERCENT
    },
    "cpu": {
      "load_1m": $LOAD_1,
      "load_5m": $LOAD_5,
      "load_15m": $LOAD_15
    }
  },
  "alerts": {
    "disk_critical": $ALERT_STATUS
  }
}
EOF
)
        echo "$JSON_PAYLOAD" >> "$SCRIPT_DIR/$LOG_FILE"

    else
        # Affichage Texte Classique
        echo "---------------------------------------------------" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "Rapport de santé du système - $DATE" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "   RAM    : $RAM_USED MB / $RAM_TOTAL MB ($RAM_PERCENT%)" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "   Disque : $DISK_USED / $DISK_TOTAL ($DISK_PERCENT%)" >> "$SCRIPT_DIR/$LOG_FILE"
        
        if [ "$ALERT_STATUS" = "true" ]; then
            echo "   [ALERTE CRITIQUE] /!\\ L'espace disque a dépassé le seuil !" >> "$SCRIPT_DIR/$LOG_FILE"
        fi

        echo "   Charge : $LOAD_1 $LOAD_5 $LOAD_15" >> "$SCRIPT_DIR/$LOG_FILE"
        echo "" >> "$SCRIPT_DIR/$LOG_FILE"
    fi

    sleep "$CHECK_INTERVAL"
done
