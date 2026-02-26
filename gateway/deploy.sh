#!/usr/bin/env bash
rsync -avz --exclude-from='.rsyncignore' --delete ./ morindin@gateway.homelab.lan:~/gateway/ && ssh morindin@gateway.homelab.lan "cd ~/gateway && docker compose up -d"
