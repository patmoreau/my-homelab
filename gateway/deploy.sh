#!/usr/bin/env bash
source .env
rsync -avz --exclude-from='.rsyncignore' --delete ./ ${HOST_USER}@${HOST}:~/${HOST_NAME} && ssh ${HOST_USER}@${HOST} "cd ~/${HOST_NAME} && docker compose up -d"
