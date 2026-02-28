#!/usr/bin/env bash
source .env
ssh ${HOST_USER}@${HOST} "cd ~/${HOST_NAME} && docker compose down"
