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
# 2. Portable Postgres
# ============================================
COPY binaries/postgres-${POSTGRES_VERSION}-linux-amd64.txz /tmp/
RUN mkdir -p /home/builder/.steampipe/db/${POSTGRES_VERSION}/postgres \
    && tar -xJf /tmp/postgres-${POSTGRES_VERSION}-linux-amd64.txz \
       -C /home/builder/.steampipe/db/${POSTGRES_VERSION}/postgres \
    && rm /tmp/postgres-${POSTGRES_VERSION}-linux-amd64.txz

# ============================================
# 3. FDW Extension
# ============================================
COPY binaries/steampipe_postgres_fdw.so.gz /tmp/
COPY binaries/steampipe_postgres_fdw.control /tmp/
COPY binaries/steampipe_postgres_fdw--1.0.sql /tmp/

RUN gunzip -c /tmp/steampipe_postgres_fdw.so.gz \
      > /home/builder/.steampipe/db/${POSTGRES_VERSION}/postgres/lib/postgresql/steampipe_postgres_fdw.so \
    && cp /tmp/steampipe_postgres_fdw.control \
          /home/builder/.steampipe/db/${POSTGRES_VERSION}/postgres/share/postgresql/extension/ \
    && cp /tmp/steampipe_postgres_fdw--1.0.sql \
          /home/builder/.steampipe/db/${POSTGRES_VERSION}/postgres/share/postgresql/extension/ \
    && rm /tmp/steampipe_postgres_fdw.*

# ============================================
# 4. Database versions.json
# ============================================
RUN echo '{"db":{"name":"embeddedDB","version":"14.19.0","install_date":"2025-01-26T00:00:00Z"},"fdw_extension":{"name":"fdwExtension","version":"2.1.4","install_date":"2025-01-26T00:00:00Z"}}' \
    > /home/builder/.steampipe/db/versions.json

# ============================================
# 5. Install plugins via steampipe (OCI download)
# ============================================
RUN chown -R builder:builder /home/builder/.steampipe

USER builder
RUN steampipe plugin install turbot/jira theapsgroup/gitlab

# ============================================
# Stage 2: Runtime image
# ============================================
ARG PROFILE=vpn
FROM wsl-base:${PROFILE}

USER root

# Build arguments
ARG GATEWAY_RELEASE=gateway.jar
ARG STEAMPIPE_PORT=9193
ARG GATEWAY_PORT=8080
ARG WIN_MOUNT=/mnt/c/devhome/projects/steamengine
ARG DEFAULT_USER=fadzi

# ============================================
# Copy pre-built steampipe from builder
# ============================================
COPY --from=steampipe-builder /usr/local/bin/steampipe /usr/local/bin/steampipe
COPY --from=steampipe-builder /home/builder/.steampipe /home/${DEFAULT_USER}/.steampipe

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

# fstab for secrets mount
RUN echo "${WIN_MOUNT}/secrets /home/${DEFAULT_USER}/.secrets none bind,nofail 0 0" > /etc/fstab

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
