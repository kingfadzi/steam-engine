# Steam Engine WSL Image
# Steampipe + Gateway ETL for Jira/GitLab → DW PostgreSQL
#
# Build: ./build.sh vpn
# Import: wsl --import steam-engine C:\wsl\steam-engine steam-engine.tar
#
# Requires: wsl-base:${PROFILE} to be built first (auto-builds if missing)
#
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
# Steampipe CLI from official RPM
# ============================================
COPY binaries/steampipe_linux_amd64.rpm /tmp/
RUN dnf install -y /tmp/steampipe_linux_amd64.rpm \
    && rm -f /tmp/steampipe_linux_amd64.rpm

# ============================================
# PostgreSQL 14 from local RPMs + utilities
# ============================================
COPY binaries/postgres/*.rpm /tmp/postgres/
RUN dnf install -y /tmp/postgres/*.rpm telnet \
    && rm -rf /tmp/postgres \
    && dnf clean all

# ============================================
# Install FDW extension to RPM postgres
# ============================================
# Steampipe embedded postgres expects FDW at:
#   <pg_dir>/lib/steampipe_postgres_fdw.so
#   <pg_dir>/share/extension/steampipe_postgres_fdw*
COPY binaries/steampipe-bundle.tgz /tmp/steampipe-bundle.tgz
RUN mkdir -p /usr/pgsql-14/lib /usr/pgsql-14/share/extension \
    && mkdir -p /tmp/fdw-extract \
    && tar -xzf /tmp/steampipe-bundle.tgz -C /tmp/fdw-extract --wildcards '*/fdw/*' \
    && cp /tmp/fdw-extract/fdw/steampipe_postgres_fdw.so /usr/pgsql-14/lib/ \
    && cp /tmp/fdw-extract/fdw/steampipe_postgres_fdw--1.0.sql /usr/pgsql-14/share/extension/ \
    && cp /tmp/fdw-extract/fdw/steampipe_postgres_fdw.control /usr/pgsql-14/share/extension/ \
    && rm -rf /tmp/fdw-extract /tmp/steampipe-bundle.tgz

# Make postgres directory writable by fadzi (needed for steampipe temp files)
RUN chown -R ${DEFAULT_USER}:${DEFAULT_USER} /usr/pgsql-14

# Mask RPM postgres service to prevent conflicts
RUN systemctl mask postgresql-14.service

# ============================================
# Systemd Services
# ============================================
COPY config/systemd/steampipe.service /etc/systemd/system/
COPY config/systemd/gateway.service /etc/systemd/system/
COPY config/systemd/home-fadzi-.steampipe-db-14.19.0-postgres.mount /etc/systemd/system/

RUN systemctl enable steampipe.service gateway.service home-fadzi-.steampipe-db-14.19.0-postgres.mount

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
# Create directory structure (owned by default user)
RUN mkdir -p /home/${DEFAULT_USER}/.steampipe/db/14.19.0/postgres \
    && mkdir -p /home/${DEFAULT_USER}/.gateway \
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
    && echo "PATH=/usr/bin:/home/${DEFAULT_USER}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/bin" >> /etc/environment

# Default user for WSL
USER ${DEFAULT_USER}
WORKDIR /home/${DEFAULT_USER}

CMD ["/sbin/init"]
