#!/usr/bin/env bash
source .env
rsync -avz --exclude-from='.rsyncignore' --delete ../shared/portainer-agent/ ${HOST_USER}@${HOST}:~/${HOST_NAME}/portainer-agent
rsync -avz --exclude-from='.rsyncignore' --exclude='portainer-agent' --delete ./ ${HOST_USER}@${HOST}:~/${HOST_NAME} && ssh ${HOST_USER}@${HOST} "cd ~/${HOST_NAME} && docker compose up -d"
