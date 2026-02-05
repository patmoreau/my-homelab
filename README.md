# My Homelab setup

## Configuration

First, create a shared Docker network so Traefik can talk to other containers:

```bash
docker network create traefik-public
```

## Services

The following services are configured in this homelab:

| Service          | Local Domain               | Description                                                                                     |
| :--------------- | :------------------------- | :---------------------------------------------------------------------------------------------- |
| **Traefik**      | `traefik.homelab.lan`      | Reverse proxy and load balancer. Manages access to all other services.                          |
| **Homepage**     | `home.homelab.lan`         | A modern, fully static, fast, secure fully proxied, highly customizable application dashboard.  |
| **Portainer**    | `portainer.homelab.lan`    | Lightweight management UI which allows you to easily manage your different Docker environments. |
| **Jellyfin**     | `jellyfin.homelab.lan`     | The Free Software Media System. Manages and streams your media.                                 |
| **Calibre-Web**  | `books.homelab.lan`        | Web app for browsing, reading and downloading eBooks stored in a Calibre database.              |
| **Transmission** | `transmission.homelab.lan` | A fast, easy, and free BitTorrent client.                                                       |

### Network

All services are connected via the `traefik-public` external network.

### Volumes & Mounts

Key persistent data and media mounts:

- `/mnt/nas-books`: Mounted to Calibre-Web for books.
- `/mnt/nas-media`: Mounted to Jellyfin (movies) and Transmission (downloads/watch).

Configure them in /etc/fstab

with a good NAS:

```text
192.168.50.1:/Multimedia /mnt/nas-media nfs defaults,soft,bg,_netdev,nfsvers=4.1,async,timeo=150,retrans=3 0 0
```

for QNAP

```text
192.168.50.1:/Multimedia /mnt/nas-media nfs defaults,nfsvers=3,soft,bg,_netdev,async,timeo=150,retrans=3 0 0
```
