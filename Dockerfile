# Steam Engine WSL Image
# Steampipe + Gateway ETL for Jira/GitLab → DW PostgreSQL
#
# Build: ./build.sh vpn
# Import: wsl --import steam-engine C:\wsl\steam-engine steam-engine.tar
#
FROM almalinux:9

# Build arguments
ARG DNS_SERVERS="8.8.8.8 8.8.4.4"
ARG JAVA_VERSION=21
ARG STEAMPIPE_PORT=9193
ARG GATEWAY_PORT=8080
ARG WIN_USER=fadzi
ARG WIN_MOUNT=/mnt/c/devhome/projects/wsl

# ============================================
# Base System
# ============================================
RUN dnf install -y \
    dnf-plugins-core \
    epel-release \
    && dnf config-manager --set-enabled crb

RUN dnf install -y --allowerasing \
    bash-completion \
    bind-utils \
    curl \
    git \
    hostname \
    jq \
    less \
    net-tools \
    procps-ng \
    sudo \
    tar \
    unzip \
    vim \
    wget \
    which \
    postgresql \
    systemd \
    && dnf clean all

# ============================================
# Java Runtime
# ============================================
RUN dnf install -y java-${JAVA_VERSION}-openjdk-headless && dnf clean all

ENV JAVA_HOME=/usr/lib/jvm/jre-${JAVA_VERSION}

# ============================================
# Steampipe Bundle
# ============================================
COPY binaries/steampipe-bundle.tgz /tmp/

RUN mkdir -p /opt/steampipe \
    && tar -xzf /tmp/steampipe-bundle.tgz -C /opt/steampipe \
    && rm /tmp/steampipe-bundle.tgz \
    && chmod +x /opt/steampipe/steampipe/steampipe

# Create steampipe config directory
RUN mkdir -p /opt/steampipe/config

# Copy steampipe plugin configs
COPY config/steampipe/*.spc /opt/steampipe/config/

ENV STEAMPIPE_INSTALL_DIR=/opt/steampipe
ENV PATH="/opt/steampipe/steampipe:/opt/steampipe/bin:${PATH}"

# ============================================
# Gateway Service
# ============================================
COPY binaries/gateway.jar /opt/gateway/gateway.jar
COPY config/gateway/application.yml /opt/gateway/application.yml

RUN mkdir -p /opt/gateway/logs

# ============================================
# Systemd Services
# ============================================
COPY config/systemd/steampipe.service /etc/systemd/system/
COPY config/systemd/gateway.service /etc/systemd/system/

RUN systemctl enable steampipe.service \
    && systemctl enable gateway.service

# ============================================
# Initialization Scripts
# ============================================
COPY scripts/init/ /opt/init/
RUN chmod +x /opt/init/*.sh

# ============================================
# Profile Scripts (login-time)
# ============================================
COPY scripts/profile.d/ /etc/profile.d/
RUN chmod +x /etc/profile.d/*.sh

# ============================================
# Utility Scripts
# ============================================
COPY scripts/bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# ============================================
# WSL Configuration
# ============================================
COPY config/wsl.conf /etc/wsl.conf

# ============================================
# User Setup
# ============================================
ARG USERNAME=steampipe
RUN useradd -m -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME}

# Set ownership
RUN chown -R ${USERNAME}:${USERNAME} /opt/steampipe /opt/gateway

# ============================================
# DNS (baked per profile)
# ============================================
ARG DNS_SERVERS
RUN for dns in ${DNS_SERVERS}; do echo "nameserver $dns" | tr -d '\r' >> /etc/resolv.conf.wsl; done && \
    echo '[ -f /etc/resolv.conf.wsl ] && sudo cp -f /etc/resolv.conf.wsl /etc/resolv.conf 2>/dev/null' > /etc/profile.d/00-dns.sh && \
    chmod +x /etc/profile.d/00-dns.sh

# ============================================
# Environment
# ============================================
ENV STEAMPIPE_PORT=${STEAMPIPE_PORT}
ENV GATEWAY_PORT=${GATEWAY_PORT}
ENV WIN_MOUNT=${WIN_MOUNT}

# Default to systemd
CMD ["/sbin/init"]
