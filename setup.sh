#!/bin/bash

set -e

# Обновление системы
echo "Обновление системы..."
sudo apt update
sudo apt upgrade -y

# Установка необходимых пакетов
echo "Установка необходимых пакетов..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Добавление Docker GPG ключа и репозитория
echo "Добавление Docker GPG ключа и репозитория..."
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Установка Docker
echo "Установка Docker..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Запуск и включение Docker
echo "Запуск и включение Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# Проверка установки Docker
echo "Проверка установки Docker..."
sudo docker --version

# Проверка инициализации Docker Swarm
if ! sudo docker info | grep -q 'Swarm: active'; then
  echo "Инициализация Docker Swarm..."
  sudo docker swarm init
else
  echo "Docker Swarm уже инициализирован."
fi

# Установка Docker Compose
echo "Установка Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Проверка установки Docker Compose
echo "Проверка установки Docker Compose..."
docker-compose --version

# Создание файлов стека для Traefik и Grafana
echo "Создание файлов стека для Traefik и Grafana..."

cat <<EOL > traefik.yml
version: '3.7'

services:
  traefik:
    image: traefik:v2.5
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    networks:
      - traefik-net
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager

networks:
  traefik-net:
    driver: overlay
EOL

cat <<EOL > grafana.yml
version: '3.7'

services:
  grafana:
    image: grafana/grafana:latest
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(\`grafana.example.com\`)"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"
    networks:
      - traefik-net
    deploy:
      replicas: 1

networks:
  traefik-net:
    external: true
EOL

# Создание файла .gitlab-ci.yml
echo "Создание файла .gitlab-ci.yml..."

cat <<EOL > .gitlab-ci.yml
stages:
  - deploy

variables:
  DOCKER_HOST: tcp://docker-swarm:2375
  TRAEFIK_STACK: traefik.yml
  GRAFANA_STACK: grafana.yml

deploy:
  stage: deploy
  script:
    - docker stack deploy -c \$TRAEFIK_STACK traefik
    - docker stack deploy -c \$GRAFANA_STACK grafana
  only:
    - master
EOL

# Деплой стеков
echo "Деплой стеков Traefik и Grafana..."
sudo docker stack deploy -c traefik.yml traefik
sudo docker stack deploy -c grafana.yml grafana

echo "Настройка завершена."