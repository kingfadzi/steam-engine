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
ARG WIN_MOUNT=/mnt/c/devhome/projects/steamengine
ARG TLS_CA_BUNDLE_URL=

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
    ca-certificates \
    curl \
    git \
    hostname \
    jq \
    less \
    net-tools \
    openssl \
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
# Corporate TLS CA Bundle + Java Cacerts
# ============================================
ARG TLS_CA_BUNDLE_URL
RUN if [ -n "$TLS_CA_BUNDLE_URL" ]; then \
        curl -fL# "$TLS_CA_BUNDLE_URL" -o /tmp/certs.zip && \
        unzip -q /tmp/certs.zip -d /tmp/certs && \
        find /tmp/certs \( -name "*.pem" -o -name "*.crt" -o -name "*.cer" \) \
            ! -name "cacerts" -exec cp {} /etc/pki/ca-trust/source/anchors/ \; && \
        update-ca-trust extract && \
        JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java) 2>/dev/null)) 2>/dev/null) && \
        if [ -n "$JAVA_HOME" ] && [ -d "$JAVA_HOME/lib/security" ]; then \
            find /tmp/certs -name "cacerts" -exec cp {} $JAVA_HOME/lib/security/cacerts \; ; \
        fi && \
        rm -rf /tmp/certs.zip /tmp/certs && \
        echo "Corporate certificates installed"; \
    else \
        echo "TLS_CA_BUNDLE_URL not set - using system defaults"; \
    fi

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
# Service User (owns steampipe/gateway)
# ============================================
RUN useradd -r -s /sbin/nologin steampipe

# Set ownership
RUN chown -R steampipe:steampipe /opt/steampipe /opt/gateway

# ============================================
# Default Login User
# ============================================
ARG DEFAULT_USER=fadzi
RUN useradd -m -s /bin/bash ${DEFAULT_USER} \
    && echo "${DEFAULT_USER}:password" | chpasswd \
    && echo "${DEFAULT_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DEFAULT_USER} \
    && chmod 0440 /etc/sudoers.d/${DEFAULT_USER}

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

# Default user for WSL
USER ${DEFAULT_USER}
WORKDIR /home/${DEFAULT_USER}

# Default to systemd
CMD ["/sbin/init"]
