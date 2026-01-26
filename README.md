# Ansible Beginner Lab

Hands-on Ansible basics using Docker containers as targets on Windows + WSL2.

## Prerequisites

- Windows 10/11 with WSL2
- Docker Desktop installed and running
- Basic terminal usage

## 0. Get a general idea about Ansible

- no need to do anything, just watch one or both videos, skip if not needed
- 4 mins intro: https://www.youtube.com/watch?v=SuUnLqWpnEM
- 16 mins intro: https://www.youtube.com/watch?v=1id6ERvfozo

(What follows is not based on any of these videos)

## 1. Set up Ubuntu in WSL

Install Ubuntu from Microsoft Store → launch it once.

```bash
sudo apt update && sudo apt upgrade -y
```

## 2. Install Ansible in a venv

```bash
sudo apt install python3-pip python3-venv -y
python3 -m venv ~/ansible-venv
source ~/ansible-venv/bin/activate
pip install ansible
ansible --version
```

(Keep the venv activated for all following commands and later on.)

## 3. Enable Docker in WSL

Docker Desktop → Settings → Resources → WSL Integration → Enable your Ubuntu distro.

If `docker` command fails later:

```bash
sudo usermod -aG docker $USER
```
(close and reopen terminal)

## 4. Create SSH-enabled test containers

```bash
mkdir -p ~/ansible-beginner-lab/{config1,config2}
cd ~/ansible-beginner-lab
```

Run both:

```bash
docker run -d --name container1 -p 2222:2222 \
  -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC \
  -e PASSWORD_ACCESS=true \
  -e USER_NAME=ansibleuser \
  -e USER_PASSWORD=root \
  -e SUDO_ACCESS=true \
  -v ~/ansible-beginner-lab/config1:/config \
  lscr.io/linuxserver/openssh-server:latest

docker run -d --name container2 -p 2223:2222 \
  -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC \
  -e PASSWORD_ACCESS=true \
  -e USER_NAME=ansibleuser \
  -e USER_PASSWORD=root \
  -e SUDO_ACCESS=true \
  -v ~/ansible-beginner-lab/config2:/config \
  lscr.io/linuxserver/openssh-server:latest
```

Check logs:

```bash
docker logs container1
```

→ User: ansibleuser / Password: root

## 5. Install Python in containers (needed for Ansible)

```bash
docker exec -it container1 ash -c "apk update && apk add python3 py3-pip sudo"
docker exec -it container2 ash -c "apk update && apk add python3 py3-pip sudo"
```

## 6. Create inventory.ini

For simplicity we use password auth here. Later you can upgrade to SSH keys (no password prompts).

```ini
[docker_targets:vars]
ansible_user=ansibleuser
ansible_ssh_pass=root
ansible_connection=ssh

[docker_targets]
container1 ansible_host=127.0.0.1 ansible_port=2222
container2 ansible_host=127.0.0.1 ansible_port=2223
```

## 7. Test connectivity

```bash
ansible -i inventory.ini docker_targets -m ping
```

If `host key changed` warning appears, execute these commands and then retry ping.

```bash
ssh-keygen -f ~/.ssh/known_hosts -R "[127.0.0.1]:2222"
ssh-keygen -f ~/.ssh/known_hosts -R "[127.0.0.1]:2223"
```

If you see `Host Key checking is enabled` error:

Run `ssh ansibleuser@127.0.0.1 -p 2222` first, type `yes` to accept fingerprint, enter password `root`, then `exit`.  
Repeat for port 2223.  
Then retry ping.

## 8. First playbook

Create a new folder `playbooks` on the same level with `inventory.ini`, then a new file `playbooks/01-first-playbook.yml` with the following content:

```yaml
---
- name: First Ansible playbook
  hosts: docker_targets
  become: yes
  tasks:
    - name: Install fd
      apk:
        name: fd
        state: present
        update_cache: yes

    - name: Create test file
      copy:
        content: "Ansible works!\n"
        dest: /tmp/ansible_test.txt
        mode: '0644'
```

This playbook has two tasks, one to install the `fd` package, another for creating a `txt` file with a fixed content and permissions.

To install a package needs sudo access, `become: yes` does this for ansible, but we also have to enable sudo support in the inventory, so add the following to the `[docker_targets:vars]` section:

```ini
ansible_become=yes
ansible_become_method=sudo
ansible_become_pass=root
```

We are ready to run the playbook, but before running the playbook for real, always test it in check mode with diff enabled:

```bash
ansible-playbook -i inventory.ini playbooks/01-first-playbook.yml --check --diff
```

What it does:
- Shows what would change (green/red diff)
- No actual changes made
- Safe way to verify logic
- Run it twice → second run should show no changes (idempotency)

Only after dry run succeeds, do the real run:

```bash
ansible-playbook -i inventory.ini playbooks/01-first-playbook.yml
```

Then verify:
```bash
ansible -i inventory.ini docker_targets -m command -a "fd"
```

```bash
ansible -i inventory.ini docker_targets -m command -a "cat /tmp/ansible_test.txt"
```

You should see a list of files and folders for the first command and "Ansible works!" for the second command.

Now if you run the playbook again, it should return that all the changes are OK (already there), no changes done (ok=3 changed=0):

```bash
...

PLAY RECAP ******************************************************************************************************************
container1                 : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
container2                 : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

## Common issues

- Docker command not found → enable WSL integration
- Permission denied on docker.sock → add user to docker group + relogin
- SSH connection reset → wrong port (must be 2222:2222, not 22)
- /usr/bin/python3 not found → install python3 + py3-pip in containers
- Missing sudo password → use ansible_become_pass
- apt module fails → because image is Alpine (uses apk). Later: switch to Ubuntu.
- to undo changes, you have two possibilites, pick one:
  - stop and remove both containers and create them again, including installing python
  - connect using ssh to each container and remove the changes manually
    - remove file from `tmp`: `sudo rm /tmp/ansible_test.txt`
    - uninstall `fd` package: `sudo apk del fd`

## Additional steps

At this stage, we have a basic idea about how Ansible works, we have simple example set up with Docker containers and a basic playbook. 

Take these additional steps to build on the current state and introduce new concepts:
- Switch to Ubuntu containers
- Use SSH keys instead of password
- Variables, handlers, roles
- Linting + Molecule testing
- GitHub Actions CI

### Switch to Ubuntu containers

