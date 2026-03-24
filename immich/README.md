# VM installation for gpu

```bash
sudo apt update
sudo apt install -y linux-image-generic-hwe-24.04 linux-modules-extra-$(uname -r)
```

```bash
lsmod | grep amdgpu
```
