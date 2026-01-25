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
ARG STEAMPIPE_RELEASE=steampipe-bundle.tgz
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
# Steampipe Bundle
# ============================================
COPY binaries/${STEAMPIPE_RELEASE} /tmp/steampipe-bundle.tgz

RUN mkdir -p /opt/steampipe \
    && tar -xzf /tmp/steampipe-bundle.tgz -C /opt/steampipe \
    && rm /tmp/steampipe-bundle.tgz \
    && chmod +x /opt/steampipe/steampipe/steampipe

# Create steampipe config directory
RUN mkdir -p /opt/steampipe/config

# Copy steampipe plugin configs
COPY config/steampipe/*.spc /opt/steampipe/config/

ENV STEAMPIPE_INSTALL_DIR=/opt/steampipe
ENV PATH="/opt/steampipe/steampipe:${PATH}"

# ============================================
# Gateway Service
# ============================================
COPY binaries/${GATEWAY_RELEASE} /opt/gateway/gateway.jar
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
# Profile Scripts (steam-engine specific)
# Numbered 06-08 to run after base's 00-05
# ============================================
COPY scripts/profile.d/*.sh /etc/profile.d/
RUN chmod 644 /etc/profile.d/06-*.sh /etc/profile.d/07-*.sh /etc/profile.d/08-*.sh

# ============================================
# Utility Scripts
# ============================================
COPY scripts/bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# ============================================
# WSL Configuration (override base if needed)
# ============================================
COPY config/wsl.conf /etc/wsl.conf

# ============================================
# Service User (owns steampipe/gateway)
# ============================================
RUN useradd -r -s /sbin/nologin steampipe

# Set ownership
RUN chown -R steampipe:steampipe /opt/steampipe /opt/gateway

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
