#!/usr/bin/env bash
rsync -avz --exclude-from='.rsyncignore' --delete ./ morindin@192.168.8.51:~/home/ && ssh morindin@192.168.8.51 "cd ~/home && docker compose up -d"
