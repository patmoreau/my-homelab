# Gateway

The deploy command

```zsh
rsync -avz --exclude-from='.rsyncignore' --delete ./ morindin@gateway.homelab.lan:~/gateway/ && ssh morindin@gateway.homelab.lan "cd ~/gateway && docker compose up -d"
```

The alias in .zshrc

```zsh
alias deploy-gateway="rsync -avz --exclude-from='.rsyncignore' --delete ./ morindin@gateway.homelab.lan:~/gateway/ && ssh morindin@gateway.homelab.lan 'cd ~/gateway && docker compose up -d'"
```
