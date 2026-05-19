#!/bin/bash

# ==============================================================================
# Script de surveillance système simple
# Récupère la date, l'usage RAM, l'espace disque et la charge CPU.
# ==============================================================================

# Définition des variables
LOG_FILE="system_health.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Séparateur visuel pour le log
echo "---------------------------------------------------" >> "$LOG_FILE"
echo "Rapport de santé du système - $DATE" >> "$LOG_FILE"
echo "---------------------------------------------------" >> "$LOG_FILE"

# 1. Analyse de la RAM (Mémoire vive)
# 'free -m' affiche la mémoire en Mégaoctets. 'awk' est utilisé pour filtrer la ligne pertinente.
echo ">> Utilisation de la Mémoire (RAM) :" >> "$LOG_FILE"
free -m | awk 'NR==2{printf "   Mémoire utilisée : %s MB / %s MB (%.2f%%)\n", $3, $2, $3*100/$2 }' >> "$LOG_FILE"

# 2. Analyse de l'Espace Disque (Partition racine '/')
# 'df -h' affiche l'espace en format lisible (Human readable).
echo ">> Utilisation de l'Espace Disque (Partition /) :" >> "$LOG_FILE"
df -h / | awk 'NR==2{printf "   Espace utilisé : %s / %s (%s)\n", $3, $2, $5}' >> "$LOG_FILE"

# 3. Analyse de la Charge CPU (Load Average)
# 'top -bn1' exécute top une seule fois. 'grep load' extrait la charge moyenne.
echo ">> Charge système globale :" >> "$LOG_FILE"
uptime | awk -F'load average:' '{ print "   Load Average :" $2 }' >> "$LOG_FILE"

echo "Rapport terminé." >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
