FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    restic \
    rsync \
    dcron \
    bash \
    curl \
    ca-certificates

# Set the working directory
WORKDIR /app

# Copy scripts and configuration files
COPY src/backup.sh /src/backup.sh
COPY src/restore.sh /src/restore.sh
COPY src/entrypoint.sh /src/entrypoint.sh

# Give execution rights on the scripts
RUN chmod +x /src/backup.sh /src/restore.sh /src/entrypoint.sh

# Create necessary directories
RUN mkdir -p /var/log

# Add healthcheck script
COPY src/healthcheck.sh /src/healthcheck.sh
RUN chmod +x /src/healthcheck.sh

# Healthcheck to ensure the container is working properly
HEALTHCHECK --interval=60s --timeout=30s --start-period=30s --retries=3 \
    CMD /src/healthcheck.sh

# Set the entrypoint
ENTRYPOINT ["/src/entrypoint.sh"]