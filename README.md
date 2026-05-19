# Linux System Monitor

Un outil en ligne de commande léger (Bash) pour surveiller la santé d'un système Linux. Il enregistre l'utilisation de la RAM, du disque et la charge CPU dans un fichier journal.

## Pourquoi ce projet ?
Ce script est conçu pour offrir une surveillance basique sans avoir à déployer des solutions lourdes comme Prometheus ou Zabbix. Idéal pour des serveurs personnels ou des Raspberry Pi.

## Prérequis
- Un système basé sur Linux ou Unix.
- Les utilitaires standards installés (`bash`, `awk`, `free`, `df`, `uptime`).

## Installation et Usage

1. Clonez le dépôt :
   \`\`\`bash
   git clone https://github.com/VOTRE_NOM/linux-sys-monitor.git
   cd linux-sys-monitor
   \`\`\`

2. Exécutez le script manuellement :
   \`\`\`bash
   ./monitor.sh
   \`\`\`

3. Lisez les résultats dans le fichier généré :
   \`\`\`bash
   cat system_health.log
   \`\`\`

## Automatisation (Cron)
Pour automatiser ce script afin qu'il s'exécute toutes les heures, ajoutez cette ligne à votre crontab (`crontab -e`) :
\`\`\`bash
0 * * * * /chemin/absolu/vers/linux-sys-monitor/monitor.sh
\`\`\`

## Fonctionnalités avancées

### Gestion des alertes
Le script intègre désormais un système d'alerte arithmétique. Par défaut, si l'utilisation de la partition racine `/` dépasse **80%**, une mention `[ALERTE CRITIQUE]` est automatiquement injectée dans le fichier `system_health.log`. 
Cela permet de repérer instantanément les anomalies lors de l'analyse des journaux.

### Gestion des logs (Logrotate)
Pour éviter que le fichier `system_health.log` ne sature l'espace disque, un fichier de configuration `logrotate` est fourni. Il archive les données chaque semaine et conserve un mois d'historique compressé.

Pour l'activer sur votre système, copiez (ou liez) le fichier de configuration dans le répertoire système de logrotate :
\`\`\`bash
sudo cp linux-sys-monitor.logrotate /etc/logrotate.d/linux-sys-monitor
sudo chown root:root /etc/logrotate.d/linux-sys-monitor
\`\`\`
Vous pouvez tester la configuration manuellement (sans l'exécuter) avec :
\`\`\`bash
sudo logrotate -d /etc/logrotate.d/linux-sys-monitor
\`\`\`
