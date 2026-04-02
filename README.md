# My Homelab setup

lxc-gateway → traefik + cloudflared + promtail agent
lxc-essere → wordpress + mariadb + promtail agent
lxc-media → jellyfin + transmission + calibre-web + promtail agent
lxc-tools → homepage + promtail agent + autres
lxc-vault → bitwarden + promtail agent
lxc-monitoring → grafana + loki + prometheus

https://docs.linuxserver.io/

terraform destroy -target=module.tools

## Dnsmasq setup

1. SSH into the router

   ```bash
   ssh root@<router_ip>
   ```

2. Get the current IP address of the router

   ```bash
   uci get dhcp.@dnsmasq[0].address
   ```

3. Add the IP address to the dnsmasq configuration

   ```bash
   uci add_list dhcp.@dnsmasq[0].address='/proxmox.homelab.lan/<proxmox_server_ip>'
   uci add_list dhcp.@dnsmasq[0].address='/qnap.homelab.lan/<qnap_server_ip>'
   uci add_list dhcp.@dnsmasq[0].address='/.homelab.lan/<gateway_vm_ip>'
   uci commit dhcp
   /etc/init.d/dnsmasq restart
   ```

4. To clean up the dnsmasq configuration

   ```bash
   uci del dhcp.@dnsmasq[0].address
   ```

## Services

The following services are configured in this homelab:

| Service          | Local Domain                                                | Description                                                                                     |
| :--------------- | :---------------------------------------------------------- | :---------------------------------------------------------------------------------------------- |
| **Traefik**      | [gateway.homelab.lan](http://gateway.homelab.lan)           | Reverse proxy and load balancer. Manages access to all other services.                          |
| **Homepage**     | [home.homelab.lan](http://home.homelab.lan)                 | A modern, fully static, fast, secure fully proxied, highly customizable application dashboard.  |
| **Portainer**    | [portainer.homelab.lan](http://portainer.homelab.lan)       | Lightweight management UI which allows you to easily manage your different Docker environments. |
| **Jellyfin**     | [jellyfin.homelab.lan](http://jellyfin.homelab.lan)         | The Free Software Media System. Manages and streams your media.                                 |
| **Calibre-Web**  | [books.homelab.lan](http://books.homelab.lan)               | Web app for browsing, reading and downloading eBooks stored in a Calibre database.              |
| **Transmission** | [transmission.homelab.lan](http://transmission.homelab.lan) | A fast, easy, and free BitTorrent client.                                                       |
| **Filebrowser**  | [filebrowser.homelab.lan](http://filebrowser.homelab.lan)   | File Browser provides a file managing interface within a specified directory.                   |

### Volumes & Mounts

Key persistent data and media mounts:

- `/mnt/nas-books`: Mounted to Calibre-Web for books.
- `/mnt/nas-docker-data`: Mounted to all services for persistent data.
- `/mnt/nas-media`: Mounted to Jellyfin (movies) and Transmission (downloads/watch).

Configure them in /etc/fstab

with a good NAS:

```text
<qnap_server_ip>:/Multimedia /mnt/nas-media nfs defaults,soft,bg,_netdev,nfsvers=4.1,async,timeo=150,retrans=3 0 0
```

for QNAP

```text
<qnap_server_ip>:/Multimedia /mnt/nas-media nfs defaults,nfsvers=3,soft,bg,_netdev,async,timeo=150,retrans=3 0 0
```
