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

# Build arguments (steam-engine specific)
ARG GATEWAY_RELEASE=gateway.jar
ARG STEAMPIPE_PORT=9193
ARG GATEWAY_PORT=8080
ARG WIN_MOUNT=/mnt/c/devhome/projects/steamengine
ARG DEFAULT_USER=fadzi

# ============================================
# Additional Packages (steam-engine specific)
# ============================================
RUN dnf install -y postgresql && dnf clean all

# ============================================
# Service User (create FIRST, before file operations)
# ============================================
RUN useradd -r -d /opt/steampipe -s /bin/bash steampipe \
    && mkdir -p /opt/steampipe /opt/gateway /opt/wsl-secrets

# ============================================
# Steampipe Directory Structure (bundle installed post-import)
# ============================================
# Bundle is NOT baked into image - Windows Defender strips binaries during WSL import.
# User runs install-steampipe.sh after import to copy bundle from Windows filesystem.
RUN mkdir -p /opt/steampipe/steampipe \
    /opt/steampipe/db \
    /opt/steampipe/config \
    /opt/steampipe/plugins \
    && chown -R steampipe:steampipe /opt/steampipe

# Copy steampipe plugin configs and example env file
COPY --chown=steampipe:steampipe config/steampipe/*.spc /opt/steampipe/config/
COPY --chown=steampipe:steampipe config/steampipe/steampipe.env.example /opt/steampipe/config/

ENV STEAMPIPE_INSTALL_DIR=/opt/steampipe
ENV STEAMPIPE_MOD_LOCATION=/opt/steampipe
ENV PATH="/opt/steampipe/steampipe:/opt/steampipe/bin:${PATH}"

# Persist ENV to /etc/environment for WSL export (docker export loses ENV)
RUN echo "STEAMPIPE_INSTALL_DIR=/opt/steampipe" >> /etc/environment \
    && echo "STEAMPIPE_MOD_LOCATION=/opt/steampipe" >> /etc/environment \
    && echo "PATH=/opt/steampipe/steampipe:/opt/steampipe/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/environment

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

RUN systemctl enable steampipe.service \
    && systemctl enable gateway.service

# ============================================
# Initialization Scripts
# ============================================
COPY scripts/init/ /opt/init/
RUN chmod +x /opt/init/*.sh

# ============================================
# Profile Scripts (steam-engine specific)
# Numbered 06-08 to run after base's 00-05
# ============================================
COPY scripts/profile.d/*.sh /etc/profile.d/
RUN chmod 644 /etc/profile.d/01-*.sh /etc/profile.d/06-*.sh /etc/profile.d/07-*.sh /etc/profile.d/08-*.sh

# ============================================
# Utility Scripts
# ============================================
COPY scripts/bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# ============================================
# WSL Configuration (override base if needed)
# ============================================
COPY config/wsl.conf /etc/wsl.conf
RUN echo "${WIN_MOUNT}/secrets /opt/wsl-secrets none bind,nofail 0 0" > /etc/fstab

# Ensure secrets directory ownership (created earlier with user)
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

# Default to systemd
CMD ["/sbin/init"]
