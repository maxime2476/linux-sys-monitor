#!/bin/bash

# ==============================================================================
# Script de surveillance système - Version 1.4 (Mode Daemon)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/monitor.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERREUR FATALE : Le fichier de configuration $CONFIG_FILE est introuvable."
    exit 1
fi

echo "Démarrage du service de surveillance..." >> "$SCRIPT_DIR/$LOG_FILE"

# Boucle infinie pour le fonctionnement en tâche de fond
while true; do
    DATE=$(date '+%Y-%m-%d %H:%M:%S')

    echo "---------------------------------------------------" >> "$SCRIPT_DIR/$LOG_FILE"
    echo "Rapport de santé du système - $DATE" >> "$SCRIPT_DIR/$LOG_FILE"
    echo "---------------------------------------------------" >> "$SCRIPT_DIR/$LOG_FILE"

    # 1. RAM
    echo ">> Utilisation de la Mémoire (RAM) :" >> "$SCRIPT_DIR/$LOG_FILE"
    free -m | awk 'NR==2{printf "   Mémoire utilisée : %s MB / %s MB (%.2f%%)\n", $3, $2, $3*100/$2 }' >> "$SCRIPT_DIR/$LOG_FILE"

    # 2. Disque
    echo ">> Utilisation de l'Espace Disque (Partition /) :" >> "$SCRIPT_DIR/$LOG_FILE"
    df -h / | awk 'NR==2{printf "   Espace utilisé : %s / %s (%s)\n", $3, $2, $5}' >> "$SCRIPT_DIR/$LOG_FILE"

    CURRENT_DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ "$CURRENT_DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
        echo "   [ALERTE CRITIQUE] /!\\ L'espace disque a dépassé le seuil de $DISK_THRESHOLD% ! (Actuel : $CURRENT_DISK_USAGE%)" >> "$SCRIPT_DIR/$LOG_FILE"
    fi

    # 3. CPU
    echo ">> Charge système globale :" >> "$SCRIPT_DIR/$LOG_FILE"
    LOAD_AVG=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    echo "   Load Average (1m, 5m, 15m) : $LOAD_AVG" >> "$SCRIPT_DIR/$LOG_FILE"

    echo "Vérification terminée. Prochaine exécution dans $CHECK_INTERVAL secondes." >> "$SCRIPT_DIR/$LOG_FILE"
    echo "" >> "$SCRIPT_DIR/$LOG_FILE"

    # Pause avant la prochaine itération
    sleep "$CHECK_INTERVAL"
done
