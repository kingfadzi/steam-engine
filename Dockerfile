FROM almalinux:9

# Base deps
RUN yum -y update && \
    yum -y install --allowerasing curl unzip ca-certificates shadow-utils && \
    yum clean all

# Install Steampipe CLI as root with the script
RUN /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/turbot/steampipe/main/scripts/install.sh)"

# Create non-root user
RUN useradd -ms /bin/bash steampipe
USER steampipe
WORKDIR /home/steampipe

# Install plugins (jira@1.1.0 for DC compatibility - 2.x uses Cloud v3 API)
RUN steampipe plugin install theapsgroup/gitlab --skip-config && \
    steampipe plugin install jira@1.1.0 --skip-config && \
    steampipe plugin install bitbucket --skip-config

# Configs will usually be mounted at runtime:
#   -v ./config:/home/steampipe/.steampipe/config

EXPOSE 9193

ENTRYPOINT ["steampipe", "service", "start", "--database-listen=network", "--database-port=9193", "--foreground"]
