# Steam Engine WSL Image
# Steampipe + Gateway ETL for Jira/GitLab → DW PostgreSQL
#
# Build: ./binaries.sh && ./build.sh vpn
# Import: wsl --import steam-engine C:\wsl\steam-engine steam-engine.tar
#
# Multi-stage build:
#   Stage 1 (Alma9): Assemble steampipe from local binaries + install plugins
#   Stage 2 (wsl-base): Runtime image
#

# Global ARG for base image (must be before any FROM)
ARG PROFILE=vpn

# ============================================
# Stage 1: Assemble steampipe on Alma9
# ============================================
FROM almalinux:9 AS steampipe-builder

RUN dnf install -y tar gzip xz

# Versions (must match binaries.sh)
ENV POSTGRES_VERSION=14.19.0
ENV FDW_VERSION=2.1.4

# Steampipe env
ENV HOME=/home/builder
ENV STEAMPIPE_INSTALL_DIR=/home/builder/.steampipe
ENV STEAMPIPE_UPDATE_CHECK=false
ENV STEAMPIPE_TELEMETRY=none

RUN useradd -m builder
WORKDIR /home/builder

# ============================================
# 1. Steampipe CLI
# ============================================
COPY binaries/steampipe_linux_amd64.tar.gz /tmp/
RUN tar -xzf /tmp/steampipe_linux_amd64.tar.gz -C /usr/local/bin \
    && rm /tmp/steampipe_linux_amd64.tar.gz

# ============================================
# 2. Prepare steampipe directories (postgres installed in Stage 2)
# ============================================
RUN mkdir -p /home/builder/.steampipe/db/${POSTGRES_VERSION} \
    && mkdir -p /home/builder/.steampipe/config

# ============================================
# 5. Install plugins from local files
# ============================================
COPY binaries/steampipe-plugin-jira.tar.gz /tmp/
COPY binaries/steampipe-plugin-gitlab.tar.gz /tmp/

# Jira plugin
RUN mkdir -p /tmp/jira-plugin \
    && tar -xzf /tmp/steampipe-plugin-jira.tar.gz -C /tmp/jira-plugin \
    && mkdir -p /home/builder/.steampipe/plugins/hub.steampipe.io/plugins/turbot/jira@latest \
    && gunzip -c /tmp/jira-plugin/steampipe-plugin-jira_linux_amd64.gz \
       > /home/builder/.steampipe/plugins/hub.steampipe.io/plugins/turbot/jira@latest/steampipe-plugin-jira.plugin \
    && chmod +x /home/builder/.steampipe/plugins/hub.steampipe.io/plugins/turbot/jira@latest/steampipe-plugin-jira.plugin \
    && mkdir -p /home/builder/.steampipe/config \
    && cp /tmp/jira-plugin/config/* /home/builder/.steampipe/config/ \
    && rm -rf /tmp/jira-plugin /tmp/steampipe-plugin-jira.tar.gz

# GitLab plugin
RUN mkdir -p /tmp/gitlab-plugin \
    && tar -xzf /tmp/steampipe-plugin-gitlab.tar.gz -C /tmp/gitlab-plugin \
    && mkdir -p /home/builder/.steampipe/plugins/hub.steampipe.io/plugins/theapsgroup/gitlab@latest \
    && gunzip -c /tmp/gitlab-plugin/steampipe-plugin-gitlab_linux_amd64.gz \
       > /home/builder/.steampipe/plugins/hub.steampipe.io/plugins/theapsgroup/gitlab@latest/steampipe-plugin-gitlab.plugin \
    && chmod +x /home/builder/.steampipe/plugins/hub.steampipe.io/plugins/theapsgroup/gitlab@latest/steampipe-plugin-gitlab.plugin \
    && cp /tmp/gitlab-plugin/config/* /home/builder/.steampipe/config/ \
    && rm -rf /tmp/gitlab-plugin /tmp/steampipe-plugin-gitlab.tar.gz

RUN chown -R builder:builder /home/builder/.steampipe

USER builder

# ============================================
# Stage 2: Runtime image
# ============================================
FROM wsl-base:${PROFILE}

USER root

# Build arguments
ARG GATEWAY_RELEASE=gateway.jar
ARG STEAMPIPE_PORT=9193
ARG GATEWAY_PORT=8080
ARG WIN_MOUNT=/mnt/c/devhome/projects/steamengine
ARG DEFAULT_USER=fadzi

# ============================================
# Install PostgreSQL 14 from local RPMs
# ============================================
COPY binaries/postgresql14-libs.rpm /tmp/
COPY binaries/postgresql14.rpm /tmp/
COPY binaries/postgresql14-server.rpm /tmp/

RUN dnf install -y /tmp/postgresql14-libs.rpm /tmp/postgresql14.rpm /tmp/postgresql14-server.rpm \
    && rm /tmp/postgresql14*.rpm

# ============================================
# Install FDW Extension into RPM postgres
# ============================================
COPY binaries/steampipe_postgres_fdw.so.gz /tmp/
COPY binaries/steampipe_postgres_fdw.control /tmp/
COPY binaries/steampipe_postgres_fdw--1.0.sql /tmp/

RUN gunzip -c /tmp/steampipe_postgres_fdw.so.gz > /usr/pgsql-14/lib/steampipe_postgres_fdw.so \
    && cp /tmp/steampipe_postgres_fdw.control /usr/pgsql-14/share/extension/ \
    && cp /tmp/steampipe_postgres_fdw--1.0.sql /usr/pgsql-14/share/extension/ \
    && rm /tmp/steampipe_postgres_fdw.* \
    && chown -R ${DEFAULT_USER}:${DEFAULT_USER} /usr/pgsql-14

# ============================================
# Copy pre-built steampipe from builder
# ============================================
COPY --from=steampipe-builder /usr/local/bin/steampipe /usr/local/bin/steampipe
COPY --from=steampipe-builder /home/builder/.steampipe /home/${DEFAULT_USER}/.steampipe

# ============================================
# Mount point for RPM postgres (bind mount in fstab)
# ============================================
RUN mkdir -p /home/${DEFAULT_USER}/.steampipe/db/14.19.0/postgres

# Create versions.json with correct digest so steampipe doesn't reinstall
RUN echo '{"db":{"name":"embeddedDB","version":"14.19.0","image_digest":"sha256:84264ef41853178707bccb091f5450c22e835f8a98f9961592c75690321093d9","install_date":"2025-01-26T00:00:00Z"},"fdw_extension":{"name":"fdwExtension","version":"2.1.4","install_date":"2025-01-26T00:00:00Z"}}' \
    > /home/${DEFAULT_USER}/.steampipe/db/versions.json

# Fix ownership
RUN chown -R ${DEFAULT_USER}:${DEFAULT_USER} /home/${DEFAULT_USER}/.steampipe

# Install utilities
RUN dnf install -y telnet && dnf clean all

# ============================================
# Systemd Services
# ============================================
COPY config/systemd/steampipe.service /etc/systemd/system/
COPY config/systemd/gateway.service /etc/systemd/system/

RUN systemctl enable steampipe.service gateway.service

# ============================================
# Profile Scripts
# ============================================
COPY scripts/profile.d/*.sh /etc/profile.d/
RUN sed -i 's/\r$//' /etc/profile.d/*.sh && chmod 644 /etc/profile.d/*.sh

# ============================================
# WSL Configuration
# ============================================
COPY config/wsl.conf /etc/wsl.conf

# ============================================
# Prepare user home directory
# ============================================
RUN mkdir -p /home/${DEFAULT_USER}/.gateway \
    && mkdir -p /home/${DEFAULT_USER}/.secrets \
    && mkdir -p /home/${DEFAULT_USER}/.local/bin

# Gateway files
COPY binaries/${GATEWAY_RELEASE} /home/${DEFAULT_USER}/.gateway/gateway.jar
COPY config/gateway/application.yml /home/${DEFAULT_USER}/.gateway/

# Init/utility scripts
COPY scripts/init/*.sh /home/${DEFAULT_USER}/.local/bin/
COPY scripts/bin/*.sh /home/${DEFAULT_USER}/.local/bin/
RUN sed -i 's/\r$//' /home/${DEFAULT_USER}/.local/bin/*.sh \
    && chmod +x /home/${DEFAULT_USER}/.local/bin/*.sh

# Set ownership
RUN chown -R ${DEFAULT_USER}:${DEFAULT_USER} /home/${DEFAULT_USER}

# fstab for mounts
RUN echo "${WIN_MOUNT}/secrets /home/${DEFAULT_USER}/.secrets none bind,nofail 0 0" > /etc/fstab \
    && echo "/usr/pgsql-14 /home/${DEFAULT_USER}/.steampipe/db/14.19.0/postgres none bind 0 0" >> /etc/fstab

# ============================================
# Environment
# ============================================
ENV STEAMPIPE_INSTALL_DIR=/home/${DEFAULT_USER}/.steampipe
ENV STEAMPIPE_MOD_LOCATION=/home/${DEFAULT_USER}/.steampipe
ENV STEAMPIPE_PORT=${STEAMPIPE_PORT}
ENV GATEWAY_PORT=${GATEWAY_PORT}
ENV WIN_MOUNT=${WIN_MOUNT}

RUN echo "STEAMPIPE_INSTALL_DIR=/home/${DEFAULT_USER}/.steampipe" >> /etc/environment \
    && echo "STEAMPIPE_MOD_LOCATION=/home/${DEFAULT_USER}/.steampipe" >> /etc/environment \
    && echo "PATH=/usr/local/bin:/home/${DEFAULT_USER}/.local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/sbin:/bin" >> /etc/environment

# Default user for WSL
USER ${DEFAULT_USER}
WORKDIR /home/${DEFAULT_USER}

CMD ["/sbin/init"]
