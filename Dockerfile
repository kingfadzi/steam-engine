# Steam Engine WSL Image
# Steampipe + Gateway ETL for Jira/GitLab → DW PostgreSQL
#
# Build: ./build.sh vpn
# Import: wsl --import steam-engine C:\wsl\steam-engine steam-engine.tar
#
# Multi-stage build:
#   Stage 1 (Alma9): Build steampipe with embedded postgres
#   Stage 2 (wsl-base): Runtime image with pre-built steampipe
#

# ============================================
# Stage 1: Build steampipe on Alma9
# ============================================
FROM almalinux:9 AS steampipe-builder

# Install dependencies
RUN dnf install -y curl tar gzip

# Install steampipe CLI
RUN curl -fsSL https://steampipe.io/install/steampipe.sh | sh

# Set up environment for steampipe
ENV HOME=/root
ENV STEAMPIPE_UPDATE_CHECK=false
ENV STEAMPIPE_TELEMETRY=none

# Initialize steampipe - this downloads embedded postgres
# Start service briefly to trigger setup, then stop
RUN steampipe service start && sleep 5 && steampipe service stop

# Copy FDW into steampipe's postgres directory
COPY binaries/steampipe-bundle.tgz /tmp/steampipe-bundle.tgz
RUN mkdir -p /tmp/fdw-extract \
    && tar -xzf /tmp/steampipe-bundle.tgz -C /tmp/fdw-extract --wildcards '*/fdw/*' \
    && PGDIR=$(ls -d /root/.steampipe/db/*/postgres) \
    && cp /tmp/fdw-extract/fdw/steampipe_postgres_fdw.so "$PGDIR/lib/" \
    && cp /tmp/fdw-extract/fdw/steampipe_postgres_fdw--1.0.sql "$PGDIR/share/extension/" \
    && cp /tmp/fdw-extract/fdw/steampipe_postgres_fdw.control "$PGDIR/share/extension/" \
    && rm -rf /tmp/fdw-extract /tmp/steampipe-bundle.tgz

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
COPY --from=steampipe-builder /root/.steampipe /home/${DEFAULT_USER}/.steampipe

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
# Ensure Unix line endings (strip CR) and make executable
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

# Persist ENV for WSL
RUN echo "STEAMPIPE_INSTALL_DIR=/home/${DEFAULT_USER}/.steampipe" >> /etc/environment \
    && echo "STEAMPIPE_MOD_LOCATION=/home/${DEFAULT_USER}/.steampipe" >> /etc/environment \
    && echo "PATH=/usr/local/bin:/home/${DEFAULT_USER}/.local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/sbin:/bin" >> /etc/environment

# Default user for WSL
USER ${DEFAULT_USER}
WORKDIR /home/${DEFAULT_USER}

CMD ["/sbin/init"]
