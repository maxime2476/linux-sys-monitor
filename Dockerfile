FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl \
    python3 \
    openssl \
    procps \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .

EXPOSE 8080

CMD ["/bin/bash", "monitor.sh"]
