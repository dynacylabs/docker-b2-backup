# Backup Container Project

This project sets up a Docker container that automates the backup of a specified directory to Backblaze B2 using `restic` and `rsync`. It also includes functionality to restore the latest backup if the target directory is empty.

## Project Structure

```
backup-container
├── src
│   ├── backup.sh       # Script to handle the backup process
│   ├── restore.sh      # Script to restore the latest backup
│   └── entrypoint.sh   # Entry point for the Docker container
├── config
│   └── crontab         # Cron job configuration for scheduled backups
├── Dockerfile           # Dockerfile to build the backup container
├── docker-compose.yml   # Docker Compose configuration for the service
└── README.md            # Project documentation
```

## Setup Instructions

1. **Clone the Repository**: Clone this repository to your local machine.

2. **Configure Backblaze B2**: Ensure you have a Backblaze B2 account and obtain your application key and bucket name. These will be needed for the `restic` configuration.

3. **Edit Configuration Files**:
   - Update the `src/backup.sh` and `src/restore.sh` scripts with your Backblaze B2 credentials and bucket information.
   - Modify the `config/crontab` file to set your desired backup schedule.

4. **Build the Docker Image**:
   Navigate to the project directory and run:
   ```
   docker build -t backup-container .
   ```

5. **Run the Docker Container**:
   Use Docker Compose to start the container:
   ```
   docker-compose up -d
   ```

## Usage

- The container will check if the mounted directory is empty on startup. If it is empty, it will restore the latest backup from Backblaze B2. If not, it will run the backup process.
- The backup process is scheduled according to the configuration in the `config/crontab` file.

## Notes

- Ensure that the directory you want to back up is properly mounted in the Docker container.
- Monitor the logs of the container to check the status of backups and restores.