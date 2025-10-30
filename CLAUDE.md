# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`qbkp` is a bash-based incremental backup system that uses rsync for efficient file synchronization and compression. It creates timestamped backups with hard-link deduplication and maintains a rolling window of the 5 most recent backups.

## Architecture

The system consists of two main bash scripts:

### create_backup.sh
The core backup engine that:
- Uses rsync with `--link-dest` to create incremental backups by hard-linking unchanged files from the latest backup
- Supports include/exclude pattern filtering for selective backups
- Creates a compressed tar.gz archive of each backup snapshot
- Maintains a "latest" symlink pointing to the most recent backup
- Automatically rotates backups, keeping only the 5 most recent archives
- Generates a manifest.txt file listing all backed-up files with metadata

Key flow:
1. Rsync copies files from source to a timestamped directory, hard-linking unchanged files from the previous backup
2. Creates a manifest of all files in the backup
3. Compresses the entire backup directory into a tar.gz archive
4. Deletes the uncompressed directory to save space
5. Updates the "latest" symlink
6. Removes backups older than the 5 most recent

### schedule_backup.sh
A cron job installer that:
- Validates script paths and creates log directories
- Adds the backup script to the user's crontab with specified schedule
- Prevents duplicate entries for the same script
- Configures logging with timestamped log files

## Configuration

Backups are configured via `~/.qbkp/config`, which is sourced by create_backup.sh if it exists. This allows setting default values for:
- SOURCE_DIR (default: $HOME)
- BACKUP_DIR (default: $HOME/.qbkp/data)
- INCLUDE_PATTERNS
- EXCLUDE_PATTERNS

To get started, copy the example config:
```bash
mkdir -p ~/.qbkp
cp config.example ~/.qbkp/config
# Then edit ~/.qbkp/config to customize your backup settings
```

## Common Commands

### Run a manual backup
```bash
./create_backup.sh
```

### Run backup with custom source and destination
```bash
./create_backup.sh -s /path/to/source -d /path/to/backup/destination
```

### Run backup with include/exclude patterns
```bash
./create_backup.sh -i '*.txt' -i 'Documents/*' -e '*.tmp' -e '.cache/'
```

### Schedule automated backups
```bash
# Run backup daily at 2 AM
./schedule_backup.sh '0 2 * * *' /path/to/create_backup.sh ~/.qbkp/cron_logs
```

### View backup logs
```bash
cat ~/.qbkp/log/backup.log
```

### List available backups
```bash
ls -lht ~/.qbkp/data/*.tar.gz
```

## Key Implementation Details

- **Incremental backups**: Uses rsync's `--link-dest` to hard-link unchanged files, saving space
- **Compression pipeline**: Uses `tar | pv | gzip` to compress with progress indication
- **Backup rotation**: Automatically keeps only the 5 most recent backups using `ls -t *.tar.gz | tail -n +6 | xargs -r rm --`
- **Filter precedence**: If include patterns are specified, an implicit `--exclude=*` is added to exclude everything not explicitly included
- **Logging**: All operations are logged to both stdout and `~/.qbkp/log/backup.log`

## TODOs

From README.md:
1. PID file - Implement locking to prevent concurrent backup operations
2. Remove old backups with no changes - Take hash of all backup archives and only keep the last N unique snapshots (deduplicate identical backups)
