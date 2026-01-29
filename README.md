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
    - `docker stop container{1,2}`
    - `docker rm container{1,2}`
    - then create the containers again:
      ```bash
      docker run -d --name container1 -p 2222:22 ansible-ubuntu-ssh
      docker run -d --name container2 -p 2223:22 ansible-ubuntu-ssh
      ```
    - you will get the same errors as before so run the ssh commands at [Step 6](#6-test-connectivity) again
  - connect using ssh to each container and remove the changes manually
    - remove file from `tmp`: `sudo rm /tmp/ansible_test.txt`
    - uninstall `tree` package: `sudo apt remove tree`

## Additional steps

At this stage, we have a basic idea about how Ansible works, we have a simple example set up with Docker containers and a basic playbook. 

Take these additional steps to build on the current state and introduce new concepts:
- Use SSH keys instead of password
- Variables, handlers, roles
- Linting
- GitHub Actions CI

### A1. Use SSH keys instead of password

We can set up a SSH key to be used to access the targets, so that we don't have to use passwords.

#### 1. Generate key pair in WSL:

An existing key could also be used, but for learning a new key would be better.

```bash
ssh-keygen -t ed25519 -C "ansible-lab-key" -f ~/.ssh/ansible_lab_key
```

#### 2. Create a new playbook to copy public key to all targets

Create `playbooks/02-copy-ssh-key.yml`:
```yaml
---
- name: Copy SSH public key to all targets
  hosts: docker_targets
  become: yes
  gather_facts: false

  vars:
    pub_key_path: "~/.ssh/ansible_lab_key.pub"

  tasks:
    - name: Ensure .ssh directory exists
      file:
        path: "~ansibleuser/.ssh"
        state: directory
        owner: ansibleuser
        group: ansibleuser
        mode: '0700'

    - name: Copy public key to authorized_keys
      authorized_key:
        user: ansibleuser
        key: "{{ lookup('file', pub_key_path) }}"
        state: present
        exclusive: no   # add, don't replace existing keys

    - name: Debug - key added
      debug:
        msg: "Public key copied to {{ inventory_hostname }}"
```

Dry-run and then run the playbook:
```bash
ansible-playbook -i inventory.ini playbooks/02-copy-ssh-key.yml --check --diff
ansible-playbook -i inventory.ini playbooks/02-copy-ssh-key.yml
```

#### 3. Update `inventory.ini` - remove `ansible_ssh_pass`, add key path:

```ini
[docker_targets:vars]
ansible_user=ansibleuser
ansible_ssh_private_key_file=~/.ssh/ansible_lab_key
ansible_connection=ssh
ansible_become=yes
ansible_become_method=sudo
ansible_become_pass=root
```

#### 4. Test with a ping:

```bash
ansible -i inventory.ini docker_targets -m ping
```
→ no password prompt should appear

#### 5. Test with a playbook:

```bash
ansible-playbook -i inventory.ini playbooks/01-first-playbook.yml --check --diff
ansible-playbook -i inventory.ini playbooks/01-first-playbook.yml
```
→ no password prompt should appear

### A2. Variables

Create `group_vars/docker_targets.yml` in the project root:

```yaml
---
package_name: tree
test_file_content: |
  Ansible variable test
  Date: {{ ansible_facts['date_time']['date'] }}
```

Create new playbook (`playbooks/03-variables-playbook.yml`):

```yaml
---
- name: Ansible playbook with variables
  hosts: docker_targets
  become: yes
  tasks:
    - name: Install package
      apt:
        name: "{{ package_name }}"
        state: present
        update_cache: yes

    - name: Create file with variable content
      copy:
        content: "{{ test_file_content }}"
        dest: /tmp/ansible_var_test.txt
        mode: '0644'
```

Run dry + real:

```bash
ansible-playbook -i inventory.ini playbooks/03-variables-playbook.yml --check --diff
ansible-playbook -i inventory.ini playbooks/03-variables-playbook.yml
```

The `tree` is most probably installed already from the first playbook, so when you run the commands above, you will see that the `Install package` is `OK`, meaning it is already done, no change needed.

Verify the second task:

```bash
ansible -i inventory.ini docker_targets -m command -a "cat /tmp/ansible_var_test.txt"
```

We already used some variables in `02-copy-ssh-key.yml` too:
```yaml
# define variable (pub_key_path):
vars:
    pub_key_path: "~/.ssh/ansible_lab_key.pub"
# ...
# use:
  - name: Copy public key to authorized_keys
        authorized_key:
          user: ansibleuser
          key: "{{ lookup('file', pub_key_path) }}"
          state: present
          exclusive: no
# a special ansible variable:
          msg: "Public key copied to {{ inventory_hostname }}"
```
In this case the `pub_key_path` variable is used with the [`lookup` plugin](https://docs.ansible.com/projects/ansible/latest/plugins/lookup.html).

The second variable, `inventory_hostname` is a [Special Ansible Variable](https://docs.ansible.com/projects/ansible/latest/reference_appendices/special_variables.html).

More information: [Using variables](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_variables.html)

### A3. Handlers

→ Handlers are tasks that only run when **notified** by another task.  
→ Notification happens only if the notifying task reports **changed** (not ok).  
→ Handlers run **at the end of the play**, after all tasks, and only once per play (even if notified multiple times).  

In the following playbook:
- We'll have a handler to restart nginx whenever notified to do so
- If any of the tasks (`Install nginx` or `Copy nginx config`) reports as changed → handler restarts nginx once at the end.
- If both tasks are ok (already installed/configured) → no notification → no restart.  

Create `playbooks/04-handlers.yml`:

```yaml
---
- name: Playbook with handler
  hosts: docker_targets
  become: yes
  tasks:
    - name: Install nginx
      apt:
        name: nginx
        state: present
        update_cache: yes
      notify: Restart nginx   # <--- calls handler if changed

    - name: Copy nginx config
      copy:
        content: |
          server {
            listen 80;
            server_name localhost;
            location / {
              return 200 "Hello from Ansible!\n";
            }
          }
        dest: /etc/nginx/sites-available/default
        mode: '0644'
      notify: Restart nginx

  handlers:
    - name: Restart nginx
      service:
        name: nginx
        state: restarted
```

#### How to test and verify how it works
Run playbook → see handler in first run → second run no handler → force change + rerun to see it again.

0. **Check the playbook** (optional):
   ```
   ansible-playbook -i inventory.ini playbooks/04-handlers.yml --check --diff
   ```

   - It shows what it would do, including diffs
   - It will fail when testing the handler, because `nginx` is not installed (yet):
   ```bash
   [ERROR]: Task failed: Module failed: Could not find the requested service nginx: host
   ```

1. **Run the playbook once** (real run):
   ```
   ansible-playbook -i inventory.ini playbooks/04-handlers.yml
   ```

   - First run: both tasks changed → handler restarts nginx.
   - Look for `RUNNING HANDLER [Restart nginx] ` in output.

2. **Run it again**:
   ```
   ansible-playbook -i inventory.ini playbooks/04-handlers.yml
   ```

   - Both tasks ok → no notification → no handler run.

3. **Force a change to trigger handler**:
   - Manually stop nginx in one container:
     ```
     ansible -i inventory.ini container1 -m command -a "service nginx stop" -b
     ```

   - Run playbook again → copy task ok, but install task ok → **no restart** (handler only restarts if notified).

   - check `nginx` status on both targets:
     ```bash
     ansible -i inventory.ini docker_targets -m command -a "service nginx status" -b
     ```
     Results should be: Container1 `* nginx is not running`, Container2 `* nginx is running`

   - To force notification, make a small change (e.g. touch a dummy file)
     ```yaml
     - name: Force handler trigger
       file:
         path: /tmp/force-handler.txt
         state: touch
       notify: Restart nginx
     ```

   - Run → handler restarts nginx.

4. **Check if nginx restarted**:
   ```
   ansible -i inventory.ini docker_targets -m command -a "service nginx status" -b
   ```

   Both containers should display: `* nginx is running`.

### A4. Roles

Roles are the main way to organize reusable Ansible code. Think of them as self-contained "modules" or "packages" for your automation.

#### What is a role

A role is a directory with a standard structure that bundles tasks, variables, files, templates, handlers etc. that belong together. Example:

```text
roles/
  webserver/
    tasks/
      main.yml          # main tasks that run when role is included
    handlers/
      main.yml          # handlers that the tasks can notify
    templates/
      nginx.conf.j2     # Jinja2 templates
    files/
      static-file.txt   # plain files to copy
    vars/
      main.yml          # role-specific variables
    defaults/
      main.yml          # default variables (can be overridden)
    meta/
      main.yml          # dependencies on other roles
```

When you use a role in a playbook:
```yaml
- hosts: webservers
  roles:
    - webserver
```
Ansible automatically runs `roles/webserver/tasks/main.yml` (and pulls in handlers, templates etc. as needed).

#### When / why should you use roles?
Use roles when:
- You repeat the same setup on multiple projects or hosts
- You want clean, readable playbooks
- You want to share/reuse code
- You need to organize complexity
- You plan to test or lint code

You don't need roles for:

- One-time 5-task playbook
- Very simple ad-hoc stuff

Rule of thumb: if you copy-paste tasks more than once → make a role.

#### Working example for a role

→ We'll call the role: `webserver`

Create `playbooks/roles/webserver` folder structure from the project root:

```bash
mkdir -p playbooks/roles/webserver/{tasks,handlers,templates}
```

`playbooks/roles/webserver/tasks/main.yml`:

```yaml
---
- name: Install nginx
  apt:
    name: nginx
    state: present
    update_cache: yes
  notify: Restart nginx

- name: Copy nginx config
  template:
    src: default.conf.j2
    dest: /etc/nginx/sites-available/default
    mode: '0644'
  notify: Restart nginx
```

`playbooks/roles/webserver/handlers/main.yml`:

```yaml
---
- name: Restart nginx
  service:
    name: nginx
    state: restarted
```

`playbooks/roles/webserver/templates/default.conf.j2` (Jinja2 template):

```jinja
server {
  listen 80;
  server_name localhost;
  location / {
    return 200 "Hello from role!\n";
  }
}
```

New playbook `playbooks/05-roles.yml`:

```yaml
---
- name: Use role
  hosts: docker_targets
  become: yes
  roles:
    - webserver
```

Run:

```bash
ansible-playbook -i inventory.ini playbooks/05-roles.yml --check --diff
ansible-playbook -i inventory.ini playbooks/05-roles.yml
```

Verify:

```bash
ansible -i inventory.ini docker_targets -m uri -a "url=http://localhost return_content=yes"
```

### A5. Linting 

We can use two tools for linting: `ansible-lint` and `yamllint`, to check for Ansible-related and YAML-related issues:
- `ansible-lint` → focuses on Ansible-specific rules (playbooks, roles, modules, deprecated features, best practices).
- `yamllint` → general YAML linter (indentation, line length, duplicate keys, syntax errors, style).

#### Installation

Install tools (in venv):

```bash
pip install ansible-lint yamllint
```

#### Configuration

Create `.ansible-lint` and `.yamllint` in project root (minimal configs):

**`.ansible-lint`**:
```yaml
exclude_paths:
  - .git
  - venv
skip_list:
  - name[no-name]  # allow unnamed tasks
  - experimental  # ignore new rules
```

**`.yamllint`**:
```yaml
extends: relaxed
rules:
  line-length: disable
  truthy: disable
```

#### Execution

Run:

```
ansible-lint .
yamllint .
```

Fix errors/warnings (e.g. indentation, trailing spaces, new line at the end of the file, missing quotes, deprecated syntax).

### A6. GitHub Actions: Lint and Syntax Check

Create `.github/workflows/lint.yml`:

```yaml
name: Lint Ansible code

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install ansible ansible-lint yamllint

      - name: Run yamllint
        run: yamllint .

      - name: Run ansible-lint
        run: ansible-lint .

      - name: Syntax check playbooks
        run: ansible-playbook --syntax-check playbooks/*.yml
```

Push this file to GitHub.  
It will run on every push/PR, check YAML syntax, ansible best practices, and style.  
Check GitHub repo → Actions tab to see it run.

### A7. Encrypt secrets with Ansible Vault

1. Create encrypted file for passwords (location is important):

   ```bash
   ansible-vault create group_vars/docker_targets/secrets.yml
   ```

   Enter vault password (remember it).

2. Inside the editor:

   ```yaml
   ansible_become_pass: root
   ansible_ssh_pass: root
   ```

3. Update inventory.ini — remove plaintext passwords, reference vault:

   ```ini
   [docker_targets:vars]
   ansible_user=ansibleuser
   ansible_ssh_private_key_file=~/.ssh/id_ed25519
   ansible_connection=ssh
   ansible_become=yes
   ansible_become_method=sudo
   # ansible_become_pass will be loaded from vault
   ```

4. Run with vault password:

   ```
   ansible-playbook -i inventory.ini playbooks/01-first-playbook.yml --vault-id @prompt
   ```

   Or use vault password file (for CI later):

   ```
   ansible-playbook -i inventory.ini playbooks/01-first-playbook.yml --vault-id vault_pass.txt
   ```

Using a vault resolves the problem of using plaintext secrets, especially on a repo.  
Using a plain `vault_pass.txt` file can be insecure, so it is better to use the repo's secrets or environment variables solution, example on GitHub:
```yaml
- name: Run playbook with vault
  run: ansible-playbook playbooks/*.yml --vault-id ${{ secrets.VAULT_PASSWORD }}
```
