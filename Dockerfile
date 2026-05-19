# Utilisation d'une image Debian légère
FROM debian:bookworm-slim

# Installation des dépendances nécessaires au script
RUN apt-get update && apt-get install -y \
    curl \
    python3 \
    openssl \
    procps \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Création du répertoire de travail
WORKDIR /app

# Copie des fichiers du projet
COPY . .

# Exposition du port pour l'export JSON
EXPOSE 8080

# Exécution du script au démarrage du conteneur
CMD ["/bin/bash", "monitor.sh"]
