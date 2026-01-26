# Steam Engine WSL Image
# Steampipe + Gateway ETL for Jira/GitLab → DW PostgreSQL
#
# Build: ./build.sh vpn
# Import: wsl --import steam-engine C:\wsl\steam-engine steam-engine.tar
# Setup: install.sh /mnt/c/path/to/steampipe-bundle.tgz
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
# Steampipe Directory Structure
# ============================================
# Binaries installed post-import via install.sh
# Runtime uses /run/steampipe (tmpfs), data persists in /opt/steampipe
RUN mkdir -p /opt/steampipe/config \
    /opt/steampipe/data \
    /opt/steampipe/internal \
    && chown -R steampipe:steampipe /opt/steampipe

# Copy steampipe plugin configs and example env file
COPY --chown=steampipe:steampipe config/steampipe/*.spc /opt/steampipe/config/
COPY --chown=steampipe:steampipe config/steampipe/steampipe.env.example /opt/steampipe/config/

# Runtime environment (steampipe runs from tmpfs)
ENV STEAMPIPE_INSTALL_DIR=/run/steampipe
ENV STEAMPIPE_MOD_LOCATION=/run/steampipe
ENV PATH="/run/steampipe/steampipe:/run/steampipe/bin:${PATH}"

# Persist ENV to /etc/environment for WSL (docker export loses ENV)
RUN echo "STEAMPIPE_INSTALL_DIR=/run/steampipe" >> /etc/environment \
    && echo "STEAMPIPE_MOD_LOCATION=/run/steampipe" >> /etc/environment \
    && echo "PATH=/run/steampipe/steampipe:/run/steampipe/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/environment

# ============================================
# Gateway Service
# ============================================
COPY --chown=steampipe:steampipe binaries/${GATEWAY_RELEASE} /opt/gateway/gateway.jar
COPY --chown=steampipe:steampipe config/gateway/application.yml /opt/gateway/application.yml

RUN mkdir -p /opt/gateway/logs \
    && chown -R steampipe:steampipe /opt/gateway

# ============================================
# Systemd Services (disabled by default, install.sh enables)
# ============================================
COPY config/systemd/steampipe.service /etc/systemd/system/
COPY config/systemd/gateway.service /etc/systemd/system/

# ============================================
# Initialization Scripts
# ============================================
COPY scripts/init/ /opt/init/
RUN chmod +x /opt/init/*.sh

# ============================================
# Profile Scripts (steam-engine specific)
# ============================================
COPY scripts/profile.d/*.sh /etc/profile.d/
RUN chmod 644 /etc/profile.d/*.sh 2>/dev/null || true

# ============================================
# Utility Scripts
# ============================================
COPY scripts/bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# ============================================
# WSL Configuration
# ============================================
COPY config/wsl.conf /etc/wsl.conf
RUN echo "${WIN_MOUNT}/secrets /opt/wsl-secrets none bind,nofail 0 0" > /etc/fstab

# Ensure secrets directory ownership
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
