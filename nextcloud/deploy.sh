#!/usr/bin/env bash
source .env
rsync -avz --exclude-from='.rsyncignore' --delete ../shared/ ${HOST_USER}@${HOST}:~/${HOST_NAME}
rsync -avz --exclude-from='.rsyncignore' --exclude='portainer-agent' --exclude='traefik-kop' --delete ./ ${HOST_USER}@${HOST}:~/${HOST_NAME} && ssh ${HOST_USER}@${HOST} "cd ~/${HOST_NAME} && docker compose up -d"
