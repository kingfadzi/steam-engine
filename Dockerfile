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
# PostgreSQL 14 from local RPMs
# ============================================
COPY binaries/postgres/*.rpm /tmp/postgres/
RUN dnf install -y /tmp/postgres/*.rpm \
    && rm -rf /tmp/postgres \
    && dnf clean all

# ============================================
# Service User
# ============================================
RUN useradd -r -d /opt/steampipe -s /bin/bash steampipe \
    && mkdir -p /opt/steampipe /opt/gateway /opt/wsl-secrets

# ============================================
# Steampipe (baked into image)
# ============================================
COPY binaries/steampipe-bundle.tgz /tmp/
RUN tar -xzf /tmp/steampipe-bundle.tgz -C /opt/steampipe \
    && rm /tmp/steampipe-bundle.tgz

# Install FDW extension to RPM postgres
RUN cp /opt/steampipe/fdw/steampipe_postgres_fdw.so /usr/pgsql-14/lib/steampipe_postgres_fdw.so \
    && cp /opt/steampipe/fdw/steampipe_postgres_fdw--1.0.sql /usr/pgsql-14/share/extension/ \
    && cp /opt/steampipe/fdw/steampipe_postgres_fdw.control /usr/pgsql-14/share/extension/ \
    && rm -rf /opt/steampipe/fdw

# Symlink steampipe db/ to RPM postgres
RUN ln -sf /usr/pgsql-14/bin /opt/steampipe/db/14.19.0/postgres/bin \
    && ln -sf /usr/pgsql-14/lib /opt/steampipe/db/14.19.0/postgres/lib \
    && ln -sf /usr/pgsql-14/share /opt/steampipe/db/14.19.0/postgres/share \
    && mkdir -p /opt/steampipe/db/14.19.0/postgres/data \
    && chown -R steampipe:steampipe /opt/steampipe/db

# Mask RPM postgres service to prevent conflicts
RUN systemctl mask postgresql-14.service

# Config files
COPY --chown=steampipe:steampipe config/steampipe/*.spc /opt/steampipe/config/
COPY --chown=steampipe:steampipe config/steampipe/steampipe.env.example /opt/steampipe/config/

# Persistent directories and permissions
RUN mkdir -p /opt/steampipe/data /opt/steampipe/internal \
    && chown -R steampipe:steampipe /opt/steampipe \
    && chmod +x /opt/steampipe/steampipe/steampipe

# Environment
ENV STEAMPIPE_INSTALL_DIR=/opt/steampipe
ENV STEAMPIPE_MOD_LOCATION=/opt/steampipe
ENV PATH="/opt/steampipe/steampipe:${PATH}"

# Persist ENV for WSL
RUN echo "STEAMPIPE_INSTALL_DIR=/opt/steampipe" >> /etc/environment \
    && echo "STEAMPIPE_MOD_LOCATION=/opt/steampipe" >> /etc/environment \
    && echo "PATH=/opt/steampipe/steampipe:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/environment

# ============================================
# Gateway Service
# ============================================
COPY --chown=steampipe:steampipe binaries/${GATEWAY_RELEASE} /opt/gateway/gateway.jar
COPY --chown=steampipe:steampipe config/gateway/application.yml /opt/gateway/application.yml

RUN mkdir -p /opt/gateway/logs \
    && chown -R steampipe:steampipe /opt/gateway

# ============================================
# Systemd Services
# ============================================
COPY config/systemd/steampipe.service /etc/systemd/system/
COPY config/systemd/gateway.service /etc/systemd/system/

RUN systemctl enable steampipe.service gateway.service

# ============================================
# Initialization Scripts
# ============================================
COPY scripts/init/ /opt/init/
RUN chmod +x /opt/init/*.sh

# ============================================
# Profile Scripts
# ============================================
COPY scripts/profile.d/*.sh /etc/profile.d/
RUN chmod 644 /etc/profile.d/*.sh 2>/dev/null || true

# ============================================
# Utility Scripts
# ============================================
COPY scripts/bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh 2>/dev/null || true

# ============================================
# WSL Configuration
# ============================================
COPY config/wsl.conf /etc/wsl.conf
RUN echo "${WIN_MOUNT}/secrets /opt/wsl-secrets none bind,nofail 0 0" > /etc/fstab

RUN chown steampipe:steampipe /opt/wsl-secrets

# ============================================
# Environment
# ============================================
ENV STEAMPIPE_PORT=${STEAMPIPE_PORT}
ENV GATEWAY_PORT=${GATEWAY_PORT}
ENV WIN_MOUNT=${WIN_MOUNT}

# Default user for WSL
USER ${DEFAULT_USER}
WORKDIR /home/${DEFAULT_USER}

CMD ["/sbin/init"]
