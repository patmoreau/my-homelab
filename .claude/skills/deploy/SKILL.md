---
name: deploy
description: >
  Deploy your code to a remote server using Ansible. This skill will help you automate the deployment process, ensuring that your application is consistently and reliably deployed to your target environment.
---

When I use command /deploy with all, use this command to deploy all services to the remote server using Ansible from the ansible directory:

```bash
ansible-playbook -i inventory/hosts.yaml site.yaml
```

When I use command /deploy with the name of one of the services, for example `gateway`, use this command to deploy the specified service to the remote server using Ansible from the ansible directory:

```bash
ansible-playbook -i inventory/hosts.yaml site.yaml --limit lxc-gateway
```
