FROM debian:11-slim

LABEL maintainer="KOBANA INSTITUICAO DE PAGAMENTO LTDA"
LABEL description="Crunchy Bridge Off-site Backup (CBOB) Docker Image"
LABEL version="2.0.0"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV CBOB_BASE_PATH=/data
ENV CBOB_LOG_PATH=/var/log/cbob
ENV CBOB_CONFIG_FILE=/etc/cbob/config
ENV TZ=UTC

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    jq \
    unzip \
    procps \
    postgresql-client \
    sudo \
    cron \
    logrotate \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf ./aws awscliv2.zip

# Add PostgreSQL repository and install pgBackRest
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null \
    && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-client-18 \
        pgbackrest \
    && rm -rf /var/lib/apt/lists/*

# Create postgres user and directories
RUN useradd -m -s /bin/bash postgres \
    && mkdir -p /data /var/log/cbob /etc/cbob /usr/local/lib/cbob \
    && chown -R postgres:postgres /data /var/log/cbob

# Copy CBOB files
COPY --chown=postgres:postgres bin/ /usr/local/bin/
COPY --chown=postgres:postgres lib/ /usr/local/lib/cbob/
COPY --chown=postgres:postgres etc/ /etc/cbob/templates/

# Make scripts executable
RUN chmod +x /usr/local/bin/cbob* \
    && chmod 644 /usr/local/lib/cbob/*.sh

# Setup cron for automated backups
RUN echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin" > /etc/cron.d/cbob \
    && echo "# Crunchy Bridge Off-site Backup" >> /etc/cron.d/cbob \
    && echo "00 06 * * * postgres /usr/local/bin/cbob sync >> /var/log/cbob/cron.log 2>&1" >> /etc/cron.d/cbob \
    && echo "00 18 * * * postgres /usr/local/bin/cbob restore-check >> /var/log/cbob/cron.log 2>&1" >> /etc/cron.d/cbob \
    && chmod 0644 /etc/cron.d/cbob

# Create entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Volume for data persistence
VOLUME ["/data", "/var/log/cbob", "/etc/cbob"]

# Switch to postgres user
USER postgres

# Set working directory
WORKDIR /data

# Entry point
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["cron"]
