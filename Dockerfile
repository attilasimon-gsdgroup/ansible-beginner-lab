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