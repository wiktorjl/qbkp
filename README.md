# qbkp - Quick Backup

A bash-based incremental backup system that uses rsync for efficient file synchronization and compression. qbkp creates timestamped backups with hard-link deduplication and maintains a configurable retention policy.

## Features

- **Incremental backups** using rsync's hard-link technology to save space
- **Compressed archives** with `.qbkp.tar.gz` format for easy identification
- **Configurable retention policy** with automatic cleanup (keeps 7 most recent backups by default)
- **Flexible filtering** with include/exclude patterns for selective backups
- **Automated scheduling** via cron jobs
- **Push notifications** via ntfy.sh (optional)
- **Safety features** - always keeps minimum of 2 backups regardless of retention setting
- **Detailed logging** with timestamps and statistics
- **Manifest generation** - each backup includes a file listing with metadata

## How It Works

qbkp uses rsync with the `--link-dest` option to create space-efficient incremental backups:

1. **First backup**: Copies all files from source to destination
2. **Subsequent backups**: Only copies changed files; unchanged files are hard-linked to the previous backup
3. **Compression**: Each backup directory is compressed into a `.qbkp.tar.gz` archive
4. **Cleanup**: Automatically removes old backups based on retention policy (configurable, default: 7, minimum: 2)
5. **Manifest**: Generates a file listing for each backup for easy inspection

This approach means you get the benefits of full backups (each backup is complete) with the space efficiency of incremental backups (unchanged files don't consume additional space).

## Quick Setup

### 1. Clone the repository

```bash
git clone https://github.com/wiktorjl/qbkp.git
cd qbkp
```

### 2. Make scripts executable

```bash
chmod +x create_backup.sh cleanup_backups.sh schedule_backup.sh
```

### 3. Create configuration file

```bash
mkdir -p ~/.qbkp
cp config.example ~/.qbkp/config
```

### 4. Edit configuration (optional)

Edit `~/.qbkp/config` to customize your backup settings:

```bash
nano ~/.qbkp/config
```

Key settings:
- `SOURCE_DIR` - directory to backup (default: `$HOME`)
- `BACKUP_DIR` - where to store backups (default: `$HOME/.qbkp/data`)
- `RETENTION_COUNT` - number of backups to keep (default: 7, minimum: 2)
- `INCLUDE_PATTERNS` - array of patterns to include
- `EXCLUDE_PATTERNS` - array of patterns to exclude
- `NTFY_TOPIC` - topic for push notifications (optional)

### 5. Run your first backup

```bash
./create_backup.sh
```

Your backup will be created in `~/.qbkp/data/` (or your configured `BACKUP_DIR`).

## Configuration

### Basic Configuration

The configuration file `~/.qbkp/config` allows you to set defaults for all backup operations:

```bash
# Source directory to backup
SOURCE_DIR="$HOME"

# Destination for backups
BACKUP_DIR="$HOME/.qbkp/data"

# Number of backups to retain (minimum 2 will always be kept)
RETENTION_COUNT=7

# Optional: Ntfy.sh topic for notifications
NTFY_TOPIC=""
```

### Include/Exclude Patterns

Control what gets backed up using patterns:

```bash
# Backup only specific directories
INCLUDE_PATTERNS=(
    "Documents/*"
    "Pictures/*"
    "*.pdf"
)

# Exclude specific files/directories
EXCLUDE_PATTERNS=(
    ".cache/"
    "node_modules/"
    "*.tmp"
    "*.log"
)
```

**Pattern examples:**
- `*.txt` - all .txt files
- `Documents/*` - everything in Documents directory
- `.cache/` - the .cache directory
- `node_modules/` - all node_modules directories

**Important:** If you specify any include patterns, only matching files will be backed up (an implicit `--exclude=*` is added).

### Setting Up Notifications

To receive push notifications about backup status:

1. **Choose a unique topic name** (e.g., `my-backups-xyz123`)
2. **Set topic in config**: `NTFY_TOPIC="your-topic-name"`
3. **Subscribe to notifications**:
   - **Mobile**: Install ntfy app ([Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy) / [iOS](https://apps.apple.com/app/ntfy/id1625396347)) and subscribe to your topic
   - **Desktop**: Visit `https://ntfy.sh/your-topic-name` in your browser
   - **CLI**: `curl -s https://ntfy.sh/your-topic-name/json`

You'll receive notifications for:
- Backup completion (with statistics)
- Backup failures (with error details)
- Cleanup operations (with space freed)

## Usage

### Creating Backups

**Basic backup** (uses config defaults):
```bash
./create_backup.sh
```

**Custom source and destination**:
```bash
./create_backup.sh -s /path/to/source -d /path/to/backup/destination
```

**With include/exclude patterns**:
```bash
# Backup only text files and documents
./create_backup.sh -i '*.txt' -i 'Documents/*'

# Exclude temporary files and caches
./create_backup.sh -e '*.tmp' -e '.cache/'

# Combine includes and excludes
./create_backup.sh -i 'Documents/*' -e '*.tmp'
```

**View help**:
```bash
./create_backup.sh -h
```

### Managing Backups

**List backups**:
```bash
ls -lht ~/.qbkp/data/*.qbkp.tar.gz
```

**View backup logs**:
```bash
cat ~/.qbkp/log/backup.log
```

**Check latest backup**:
```bash
ls -l ~/.qbkp/data/latest
```

### Cleaning Up Old Backups

The `cleanup_backups.sh` script allows manual control over backup retention:

**Preview what would be deleted** (dry run):
```bash
./cleanup_backups.sh --dry-run
```

**Delete old backups** (keeps configured retention count):
```bash
./cleanup_backups.sh
```

**Move old backups to /tmp** (instead of deleting):
```bash
./cleanup_backups.sh --move-to-tmp
```

**Override retention count**:
```bash
./cleanup_backups.sh --retain 10
```

**View cleanup logs**:
```bash
cat ~/.qbkp/log/cleanup.log
```

**Cleanup help**:
```bash
./cleanup_backups.sh --help
```

### Scheduling Automated Backups

Use `schedule_backup.sh` to set up automated backups via cron:

```bash
# Daily backup at 2 AM
./schedule_backup.sh '0 2 * * *' /path/to/create_backup.sh ~/.qbkp/cron_logs

# Backup every 6 hours
./schedule_backup.sh '0 */6 * * *' /path/to/create_backup.sh ~/.qbkp/cron_logs

# Weekly backup (Sunday at 3 AM)
./schedule_backup.sh '0 3 * * 0' /path/to/create_backup.sh ~/.qbkp/cron_logs
```

**Cron schedule format**: `minute hour day month day_of_week`
- `0 2 * * *` - daily at 2:00 AM
- `30 14 * * 5` - every Friday at 2:30 PM
- `0 */4 * * *` - every 4 hours

**View cron jobs**:
```bash
crontab -l
```

**Remove a cron job**:
```bash
crontab -e  # Edit and delete the line
```

## Examples

### Example 1: Full home directory backup

```bash
# Use default config (backs up $HOME to ~/.qbkp/data)
./create_backup.sh
```

### Example 2: Backup specific directories

```bash
# Edit config to include only important directories
cat >> ~/.qbkp/config << 'EOF'
INCLUDE_PATTERNS=(
    "Documents/*"
    "Pictures/*"
    "Projects/*"
    ".config/*"
)
EOF

./create_backup.sh
```

### Example 3: Exclude large/temporary files

```bash
# Edit config to exclude unnecessary files
cat >> ~/.qbkp/config << 'EOF'
EXCLUDE_PATTERNS=(
    "*.iso"
    "*.dmg"
    ".cache/"
    "Downloads/*"
    "node_modules/"
    "__pycache__/"
    "*.tmp"
)
EOF

./create_backup.sh
```

### Example 4: Backup documents to external drive

```bash
./create_backup.sh -s ~/Documents -d /mnt/external/backups -i '*.pdf' -i '*.docx'
```

### Example 5: Test cleanup without deleting

```bash
# See what would be deleted
./cleanup_backups.sh --dry-run

# If satisfied, actually clean up
./cleanup_backups.sh
```

## File Structure

```
~/.qbkp/
├── config              # User configuration file
├── data/              # Backup storage directory
│   ├── backup_20231215_140532.qbkp.tar.gz
│   ├── backup_20231216_140522.qbkp.tar.gz
│   └── latest -> backup_20231216_140522.qbkp.tar.gz
└── log/
    ├── backup.log     # Backup operation logs
    └── cleanup.log    # Cleanup operation logs
```

## Restoring from Backup

To restore files from a backup:

```bash
# Extract a backup
tar -xzf ~/.qbkp/data/backup_YYYYMMDD_HHMMSS.qbkp.tar.gz -C /tmp/

# View contents
ls -la /tmp/backup_YYYYMMDD_HHMMSS/

# Copy specific files back
cp -r /tmp/backup_YYYYMMDD_HHMMSS/path/to/file ~/restore/location/
```

Or extract specific files directly:

```bash
# List files in backup
tar -tzf ~/.qbkp/data/backup_YYYYMMDD_HHMMSS.qbkp.tar.gz | less

# Extract specific file
tar -xzf ~/.qbkp/data/backup_YYYYMMDD_HHMMSS.qbkp.tar.gz -C /tmp/ backup_YYYYMMDD_HHMMSS/path/to/file
```

## Troubleshooting

### Backup fails with "cannot create directory"

Ensure the backup directory exists and is writable:
```bash
mkdir -p ~/.qbkp/data
chmod 755 ~/.qbkp/data
```

### Notifications not working

1. Check that `NTFY_TOPIC` is set in `~/.qbkp/config`
2. Verify curl is installed: `which curl`
3. Test manually: `curl -d "test" https://ntfy.sh/your-topic-name`

### Cron job not running

1. Check cron is running: `systemctl status cron` or `ps aux | grep cron`
2. Verify the script has execute permissions: `ls -l create_backup.sh`
3. Check cron logs: `grep CRON /var/log/syslog` (Ubuntu/Debian) or `journalctl -u crond` (Fedora/CentOS)
4. Ensure paths in crontab are absolute paths

### Old backups not being cleaned up

1. Check retention setting in `~/.qbkp/config`
2. Review cleanup logs: `cat ~/.qbkp/log/cleanup.log`
3. Run manual cleanup with dry-run: `./cleanup_backups.sh --dry-run`
4. Note: Minimum of 2 backups are always kept for safety

## Requirements

- Bash 4.0+
- rsync
- tar
- gzip
- pv (pipe viewer, for progress indication)
- curl (optional, for notifications)
- numfmt (part of coreutils, for human-readable sizes)

Install dependencies on:

**Ubuntu/Debian**:
```bash
sudo apt-get install rsync tar gzip pv curl coreutils
```

**Fedora/CentOS**:
```bash
sudo dnf install rsync tar gzip pv curl coreutils
```

**macOS**:
```bash
brew install rsync pv coreutils
```

## License

This project is open source. Feel free to use and modify as needed.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## TODOs

Future improvements planned:

1. **PID file** - Implement locking to prevent concurrent backup operations
2. **Remove old backups with no changes** - Take hash of all backup archives and only keep the last N unique snapshots (deduplicate identical backups)