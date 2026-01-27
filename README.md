# Ansible Beginner Lab

Hands-on Ansible basics using Docker containers as targets on Windows + WSL2.

## Prerequisites

- Windows 10/11 with WSL2
- Docker Desktop installed and running
- Basic terminal usage
- Basic Docker knowledge

## 0. Get a general idea about Ansible

- no need to do anything, just watch one or both (recommended) videos, skip if not needed
- 4 mins very basic intro: https://www.youtube.com/watch?v=SuUnLqWpnEM
- 16 mins intro with a bit more details: https://www.youtube.com/watch?v=1id6ERvfozo

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

## 4. Create SSH-enabled containers for testing

Custom image based on Ubuntu, installing necessary software, adding password access, creating ansibleuser and exposing ssh port.

### Dockerfile

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
        openssh-server \
        python3 \
        python3-apt \
        sudo \
    && mkdir /var/run/sshd \
    && useradd -m -s /bin/bash ansibleuser \
    && echo 'ansibleuser:root' | chpasswd \
    && echo 'root:root' | chpasswd \
    && echo 'ansibleuser ALL=(ALL) ALL' > /etc/sudoers.d/ansibleuser \
    && chmod 0440 /etc/sudoers.d/ansibleuser \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
```

### Build and run

```bash
docker build -t ansible-ubuntu-ssh .
docker run -d --name container1 -p 2222:22 ansible-ubuntu-ssh
docker run -d --name container2 -p 2223:22 ansible-ubuntu-ssh
```

Check logs if needed:

```bash
docker logs container1
```

→ User: ansibleuser / Password: root

## 5. Create inventory.ini

For simplicity we use password auth here. Later you can upgrade to SSH keys (no password prompts).

```ini
[docker_targets:vars]
ansible_user=ansibleuser
ansible_ssh_pass=root
ansible_connection=ssh
ansible_become=yes
ansible_become_method=sudo
ansible_become_pass=root

[docker_targets]
container1 ansible_host=127.0.0.1 ansible_port=2222
container2 ansible_host=127.0.0.1 ansible_port=2223
```

## 6. Test connectivity

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

## 7. First playbook

Create a new folder `playbooks` on the same level with `inventory.ini`, then a new file `playbooks/01-first-playbook.yml` with the following content:

```yaml
---
- name: First Ansible playbook
  hosts: docker_targets
  become: yes
  tasks:
    - name: Install tree
      apt:
        name: tree
        state: present
        update_cache: yes

    - name: Create test file
      copy:
        content: "Ansible works!\n"
        dest: /tmp/ansible_test.txt
        mode: '0644'
```

This playbook has two tasks, one to install the `tree` package, which is not present by default in Ubuntu, then another task for creating a `txt` file with a fixed content and permissions. These tasks are based on different Ansible modules, `apt` is the package manager for Ubuntu/Debian distros, `copy` is a command to copy files or content to remote hosts.

All these Ansible modules are documented in the Ansible docs:
  
- **apt module** (install packages on Debian/Ubuntu):  
  https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_module.html

- **copy module** (copy files or content to remote hosts):  
  https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html

- **All built-in modules** (search for others):  
  https://docs.ansible.com/ansible/latest/collections/ansible/builtin/index.html

- **Full Ansible documentation** (start here for more):  
  https://docs.ansible.com/ansible/latest/index.html

First, let's refresh the package manager cache (this is important):

```bash
ansible -i inventory.ini docker_targets -m command -a "apt-get update"
```

then check if `tree` is available on  the containers:

```bash 
ansible -i inventory.ini docker_targets -m command -a "tree --version"
```

You should see something like this, meaning that it is not installed:

```bash
(ansible-venv) user@ubuntu-wsl:~/ansible-beginner-lab$ ansible -i inventory.ini docker_targets -m command -a "tree --version"
[ERROR]: Task failed: Module failed: Error executing command: [Errno 2] No such file or directory: b'tree'
...
```

Before running the playbook for real, let's test it in check mode with diff enabled:

```bash
ansible-playbook -i inventory.ini playbooks/01-first-playbook.yml --check --diff
```

What it does:
- Shows what would change (green/red diff)
- No actual changes made
- Safe way to verify logic
- It will also show issues early

Only after dry run succeeds, do the real run:

```bash
ansible-playbook -i inventory.ini playbooks/01-first-playbook.yml
```

Then verify:
```bash
ansible -i inventory.ini docker_targets -m command -a "tree --version"
```

```bash
ansible -i inventory.ini docker_targets -m command -a "cat /tmp/ansible_test.txt"
```

You should see the version of `tree` for the first command and `Ansible works!` for the second command.

Now if you run the playbook again, it should return that all the changes are OK (already there), no changes done (ok=3 changed=0):

```bash
...

TASK [Install tree] ******************************************************************************************************************
ok: [container2]
ok: [container1]

******************************************************************************************************************
ok: [container2]
ok: [container1]

PLAY RECAP ******************************************************************************************************************
container1                 : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
container2                 : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

## Common issues

- Docker command not found → enable WSL integration
- Permission denied on docker.sock → add user to docker group + relogin
- to undo changes, you have two possibilites, pick one:
  - stop and remove both containers and create them again
  - connect using ssh to each container and remove the changes manually
    - remove file from `tmp`: `sudo rm /tmp/ansible_test.txt`
    - uninstall `tree` package: `sudo apt remove tree`

## Additional steps

At this stage, we have a basic idea about how Ansible works, we have a simple example set up with Docker containers and a basic playbook. 

Take these additional steps to build on the current state and introduce new concepts:
- Use SSH keys instead of password
- Variables, handlers, roles
- Linting + Molecule testing
- GitHub Actions CI

### Switch to Ubuntu containers

