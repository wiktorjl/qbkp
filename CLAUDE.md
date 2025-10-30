# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`qbkp` is a bash-based incremental backup system that uses rsync for efficient file synchronization and compression. It creates timestamped backups with hard-link deduplication and maintains a configurable retention policy (default: 7 most recent backups, minimum: 2 for safety).

## Architecture

The system consists of three main bash scripts:

### create_backup.sh
The core backup engine that:
- Uses rsync with `--link-dest` to create incremental backups by hard-linking unchanged files from the latest backup
- Supports include/exclude pattern filtering for selective backups
- Creates a compressed archive with `.qbkp.tar.gz` extension to identify qbkp backups
- Maintains a "latest" symlink pointing to the most recent backup
- Automatically rotates backups based on configurable retention policy (default: 7, minimum: 2)
- Generates a manifest.txt file listing all backed-up files with metadata
- Sends push notifications via ntfy.sh on backup completion, failure, or cleanup (optional)

Key flow:
1. Rsync copies files from source to a timestamped directory, hard-linking unchanged files from the previous backup
2. Creates a manifest of all files in the backup
3. Compresses the entire backup directory into a `.qbkp.tar.gz` archive
4. Deletes the uncompressed directory to save space
5. Updates the "latest" symlink
6. Runs intelligent cleanup to maintain retention policy (keeps configured number of backups, minimum 2)

### cleanup_backups.sh
A standalone cleanup utility that:
- Manually triggers backup cleanup based on retention policy
- Supports `--dry-run` mode to preview what would be deleted
- Supports `--move-to-tmp` mode to preserve files in /tmp instead of deleting
- Ensures at least 2 backups are always kept for safety
- Sends ntfy.sh notifications about cleanup operations
- Logs all operations to `~/.qbkp/log/cleanup.log`

### schedule_backup.sh
A cron job installer that:
- Validates script paths and creates log directories
- Adds the backup script to the user's crontab with specified schedule
- Prevents duplicate entries for the same script
- Configures logging with timestamped log files

## Configuration

Backups are configured via `~/.qbkp/config`, which is sourced by create_backup.sh and cleanup_backups.sh if it exists. This allows setting default values for:
- SOURCE_DIR (default: $HOME)
- BACKUP_DIR (default: $HOME/.qbkp/data)
- RETENTION_COUNT (default: 7, minimum enforced: 2)
- INCLUDE_PATTERNS
- EXCLUDE_PATTERNS
- NTFY_TOPIC (optional: topic for push notifications via ntfy.sh)

To get started, copy the example config:
```bash
mkdir -p ~/.qbkp
cp config.example ~/.qbkp/config
# Then edit ~/.qbkp/config to customize your backup settings
```

### Setting up notifications

To receive push notifications about backup status:

1. Choose a unique topic name (e.g., `my-backups-xyz123`)
2. Set `NTFY_TOPIC="your-topic-name"` in `~/.qbkp/config`
3. Subscribe to notifications:
   - **Mobile**: Install the ntfy app ([Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy) / [iOS](https://apps.apple.com/app/ntfy/id1625396347)) and subscribe to your topic
   - **Desktop**: Visit `https://ntfy.sh/your-topic-name` in your browser
   - **CLI**: `curl -s https://ntfy.sh/your-topic-name/json`

Notifications are sent for:
- **Backup success**: Backup completion with statistics (files, size, duration)
- **Backup failure**: Any error during backup with relevant details
- **Cleanup**: Summary of deleted/moved backups with space freed

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
ls -lht ~/.qbkp/data/*.qbkp.tar.gz
```

### Clean up old backups manually
```bash
# Preview what would be deleted
./cleanup_backups.sh --dry-run

# Delete old backups (keeps configured retention count)
./cleanup_backups.sh

# Move old backups to /tmp instead of deleting
./cleanup_backups.sh --move-to-tmp

# Keep 10 most recent backups (override config)
./cleanup_backups.sh --retain 10
```

### View cleanup logs
```bash
cat ~/.qbkp/log/cleanup.log
```

## Key Implementation Details

- **Archive naming**: Backups use `.qbkp.tar.gz` extension (e.g., `backup_20250930_143022.qbkp.tar.gz`) to identify qbkp-managed files
- **Incremental backups**: Uses rsync's `--link-dest` to hard-link unchanged files, saving space
- **Compression pipeline**: Uses `tar | pv | gzip` to compress with progress indication
- **Intelligent cleanup**:
  - Configurable retention via `RETENTION_COUNT` in config (default: 7)
  - Always keeps minimum of 2 backups for safety, regardless of retention setting
  - Only targets files with `.qbkp.tar.gz` extension
  - Calculates space freed and sends notifications
  - Supports dry-run and move-to-tmp modes for safe testing
- **Filter precedence**: If include patterns are specified, an implicit `--exclude=*` is added to exclude everything not explicitly included
- **Logging**: All operations are logged to stdout and respective log files (`backup.log`, `cleanup.log`)
- **Notifications**: Uses ntfy.sh for push notifications (requires curl). Notifications are sent with appropriate priority levels (default for success, high for failures) and emoji tags for visual distinction

## TODOs

From README.md:
1. PID file - Implement locking to prevent concurrent backup operations
2. Remove old backups with no changes - Take hash of all backup archives and only keep the last N unique snapshots (deduplicate identical backups)
