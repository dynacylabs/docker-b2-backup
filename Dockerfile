FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    restic \
    rsync \
    dcron \
    bash \
    curl \
    ca-certificates \
    shadow

# Create backup user and group
RUN addgroup -g 1000 backup && \
    adduser -u 1000 -G backup -s /bin/bash -D backup

# Set the working directory
WORKDIR /app

# Copy scripts and configuration files
COPY src/backup.sh /src/backup.sh
COPY src/restore.sh /src/restore.sh
COPY src/entrypoint.sh /src/entrypoint.sh

# Give execution rights on the scripts
RUN chmod +x /src/backup.sh /src/restore.sh /src/entrypoint.sh

# Create necessary directories with proper permissions
RUN mkdir -p /var/log && \
    chown -R backup:backup /var/log /src

# Add healthcheck script
COPY src/healthcheck.sh /src/healthcheck.sh
RUN chmod +x /src/healthcheck.sh

# Switch to backup user by default
USER backup

# Set the entrypoint
ENTRYPOINT ["/src/entrypoint.sh"]