#!/bin/bash

# ==============================================================================
# Script de surveillance système - Version 1.2 (Fiabilité /proc)
# ==============================================================================

LOG_FILE="system_health.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Configuration du seuil d'alerte (en pourcentage)
DISK_THRESHOLD=80

echo "---------------------------------------------------" >> "$LOG_FILE"
echo "Rapport de santé du système - $DATE" >> "$LOG_FILE"
echo "---------------------------------------------------" >> "$LOG_FILE"

# 1. Analyse de la RAM
echo ">> Utilisation de la Mémoire (RAM) :" >> "$LOG_FILE"
free -m | awk 'NR==2{printf "   Mémoire utilisée : %s MB / %s MB (%.2f%%)\n", $3, $2, $3*100/$2 }' >> "$LOG_FILE"

# 2. Analyse de l'Espace Disque & Logique d'Alerte
echo ">> Utilisation de l'Espace Disque (Partition /) :" >> "$LOG_FILE"
df -h / | awk 'NR==2{printf "   Espace utilisé : %s / %s (%s)\n", $3, $2, $5}' >> "$LOG_FILE"

CURRENT_DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$CURRENT_DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
    echo "   [ALERTE CRITIQUE] /!\\ L'espace disque a dépassé le seuil de $DISK_THRESHOLD% ! (Actuel : $CURRENT_DISK_USAGE%)" >> "$LOG_FILE"
    echo "[ALERTE] Espace disque critique enregistré."
fi

# 3. Analyse de la Charge CPU (Lecture robuste via le pseudo-système de fichiers)
echo ">> Charge système globale :" >> "$LOG_FILE"
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
echo "   Load Average (1m, 5m, 15m) : $LOAD_AVG" >> "$LOG_FILE"

echo "Rapport terminé." >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
