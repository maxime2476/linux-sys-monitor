#!/bin/bash

# ==============================================================================
# Script de surveillance système - Version 1.3 (Séparation Code/Config)
# ==============================================================================

# Détection du dossier où se trouve le script (sécurité pour exécution via cron)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/monitor.conf"

# Chargement du fichier de configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERREUR FATALE : Le fichier de configuration $CONFIG_FILE est introuvable."
    exit 1
fi

DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "---------------------------------------------------" >> "$SCRIPT_DIR/$LOG_FILE"
echo "Rapport de santé du système - $DATE" >> "$SCRIPT_DIR/$LOG_FILE"
echo "---------------------------------------------------" >> "$SCRIPT_DIR/$LOG_FILE"

# 1. Analyse de la RAM
echo ">> Utilisation de la Mémoire (RAM) :" >> "$SCRIPT_DIR/$LOG_FILE"
free -m | awk 'NR==2{printf "   Mémoire utilisée : %s MB / %s MB (%.2f%%)\n", $3, $2, $3*100/$2 }' >> "$SCRIPT_DIR/$LOG_FILE"

# 2. Analyse de l'Espace Disque & Logique d'Alerte
echo ">> Utilisation de l'Espace Disque (Partition /) :" >> "$SCRIPT_DIR/$LOG_FILE"
df -h / | awk 'NR==2{printf "   Espace utilisé : %s / %s (%s)\n", $3, $2, $5}' >> "$SCRIPT_DIR/$LOG_FILE"

CURRENT_DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$CURRENT_DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
    echo "   [ALERTE CRITIQUE] /!\\ L'espace disque a dépassé le seuil de $DISK_THRESHOLD% ! (Actuel : $CURRENT_DISK_USAGE%)" >> "$SCRIPT_DIR/$LOG_FILE"
    echo "[ALERTE] Espace disque critique enregistré."
fi

# 3. Analyse de la Charge CPU
echo ">> Charge système globale :" >> "$SCRIPT_DIR/$LOG_FILE"
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
echo "   Load Average (1m, 5m, 15m) : $LOAD_AVG" >> "$SCRIPT_DIR/$LOG_FILE"

echo "Rapport terminé." >> "$SCRIPT_DIR/$LOG_FILE"
echo "" >> "$SCRIPT_DIR/$LOG_FILE"
