#!/bin/bash

CONFIG_FILE="$HOME/.qbkp/config"
DEFAULT_SOURCE_DIR="$HOME"
DEFAULT_BACKUP_DIR="$HOME/.qbkp/data"
DEFAULT_RETENTION_COUNT=7
INCLUDE_PATTERNS=()
EXCLUDE_PATTERNS=()
DATETIME=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup_$DATETIME"
LATEST_LINK="latest"
LOG_FILE="$HOME/.qbkp/log/backup.log"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

RETENTION_COUNT="${RETENTION_COUNT:-$DEFAULT_RETENTION_COUNT}"


usage() {
    echo "Usage: $0 [-s source_dir] [-d backup_dir] [-i include_pattern] [-e exclude_pattern]"
    echo "  -s: Source directory (default: $DEFAULT_SOURCE_DIR)"
    echo "  -d: Backup directory (default: $DEFAULT_BACKUP_DIR)"
    echo "  -i: Include pattern (can be used multiple times)"
    echo "  -e: Exclude pattern (can be used multiple times)"
    echo ""
    echo "Pattern examples:"
    echo "  -i '*.txt'      : Include all .txt files"
    echo "  -e '*.tmp'      : Exclude all .tmp files"
    echo "  -i 'Documents/*': Include all files in Documents directory"
    echo "  -e '.cache/'    : Exclude .cache directory"
    exit 1
}

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

send_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-default}"
    local tags="${4:-}"

    if [ -z "$NTFY_TOPIC" ]; then
        return 0
    fi

    curl -s -o /dev/null \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        -d "$message" \
        "https://ntfy.sh/$NTFY_TOPIC"
}

cleanup_old_backups() {
    local backup_dir="$1"
    local retention_count="$2"
    local dry_run="${3:-false}"
    local move_to_tmp="${4:-false}"

    cd "$backup_dir" || return 1

    # Count only qbkp backup files
    local total_backups=$(ls -1 *.qbkp.tar.gz 2>/dev/null | wc -l)

    if [ "$total_backups" -eq 0 ]; then
        log_message "No backups found to clean up"
        return 0
    fi

    # Calculate target: keep at least 2 backups, or retention_count if larger
    local target_remaining=$retention_count
    if [ "$target_remaining" -lt 2 ]; then
        target_remaining=2
    fi

    # Calculate how many to delete
    local to_delete=$((total_backups - target_remaining))

    if [ "$to_delete" -le 0 ]; then
        log_message "No cleanup needed. Current backups: $total_backups, Target: $target_remaining"
        return 0
    fi

    # Get list of files to delete (oldest first, skipping the newest N)
    local files_to_delete=$(ls -t *.qbkp.tar.gz | tail -n "+$((target_remaining + 1))")

    if [ -z "$files_to_delete" ]; then
        log_message "No backups to delete after safety checks"
        return 0
    fi

    # Calculate space to be freed
    local space_freed=0
    local deleted_count=0
    local cleanup_list=""

    for file in $files_to_delete; do
        local file_size=$(du -b "$file" 2>/dev/null | cut -f1)
        space_freed=$((space_freed + file_size))
        deleted_count=$((deleted_count + 1))
        cleanup_list="${cleanup_list}  - $file\n"

        if [ "$dry_run" = "true" ]; then
            log_message "[DRY RUN] Would delete: $file"
        elif [ "$move_to_tmp" = "true" ]; then
            local tmp_dir="/tmp/qbkp_cleanup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$tmp_dir"
            mv "$file" "$tmp_dir/" && log_message "Moved to $tmp_dir: $file"
        else
            rm -f "$file" && log_message "Deleted old backup: $file"
        fi
    done

    # Convert bytes to human readable
    local space_freed_human=$(numfmt --to=iec-i --suffix=B $space_freed 2>/dev/null || echo "${space_freed} bytes")

    # Log cleanup summary
    log_message "Cleanup summary: $deleted_count backup(s) processed, $space_freed_human freed"
    log_message "Remaining backups: $((total_backups - deleted_count))"

    # Send notification
    local action="Deleted"
    if [ "$dry_run" = "true" ]; then
        action="Would delete"
    elif [ "$move_to_tmp" = "true" ]; then
        action="Moved to /tmp"
    fi

    send_notification "Backup Cleanup Completed" \
        "$action: $deleted_count backup(s)
Space freed: $space_freed_human
Remaining: $((total_backups - deleted_count)) backup(s)" \
        "default" \
        "broom,floppy_disk"

    return 0
}

while getopts "s:d:i:e:h" opt; do
    case $opt in
        s) SOURCE_DIR="$OPTARG";;
        d) BACKUP_DIR="$OPTARG";;
        i) INCLUDE_PATTERNS+=("$OPTARG");;
        e) EXCLUDE_PATTERNS+=("$OPTARG");;
        h) usage;;
        ?) usage;;
    esac
done

SOURCE_DIR="${SOURCE_DIR:-$DEFAULT_SOURCE_DIR}"
BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"

if [ ! -d "$SOURCE_DIR" ]; then
    log_message "Error: Source directory $SOURCE_DIR does not exist"
    send_notification "Backup Failed" \
        "Source directory does not exist: $SOURCE_DIR" \
        "high" \
        "warning,floppy_disk"
    exit 1
fi

mkdir -p "$BACKUP_DIR"
if [ ! -d "$BACKUP_DIR" ]; then
    log_message "Error: Cannot create backup directory $BACKUP_DIR"
    send_notification "Backup Failed" \
        "Cannot create backup directory: $BACKUP_DIR" \
        "high" \
        "warning,floppy_disk"
    exit 1
fi

log_message "Starting backup from $SOURCE_DIR to $BACKUP_DIR/$BACKUP_NAME"
start_time=$(date +%s)

FILTER_RULES=()
for pattern in "${INCLUDE_PATTERNS[@]}"; do
    FILTER_RULES+=("--include=$pattern")
done
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    FILTER_RULES+=("--exclude=$pattern")
done

if [ ${#INCLUDE_PATTERNS[@]} -gt 0 ]; then
    FILTER_RULES+=("--exclude=*")
fi


log_message "Filter rules:"
for rule in "${FILTER_RULES[@]}"; do
    log_message "  $rule"
done

rsync -avP --delete \
    --link-dest="$BACKUP_DIR/$LATEST_LINK" \
    "${FILTER_RULES[@]}" \
    "$SOURCE_DIR/" \
    "$BACKUP_DIR/$BACKUP_NAME/" \
    2>> "$LOG_FILE"

if [ $? -eq 0 ]; then
    log_message "Creating manifest file"
    find "$BACKUP_DIR/$BACKUP_NAME" -type f -exec ls -lh {} \; > "$BACKUP_DIR/$BACKUP_NAME/manifest.txt"

    num_files=$(find "$BACKUP_DIR/$BACKUP_NAME" -type f | wc -l)

    log_message "Creating compressed archive"
    compression_start_time=$(date +%s)
    tar -cf - -C "$BACKUP_DIR" "$BACKUP_NAME" | pv | gzip > "$BACKUP_DIR/$BACKUP_NAME.qbkp.tar.gz"
    compression_end_time=$(date +%s)

    if [ $? -eq 0 ]; then
        rm -rf "$BACKUP_DIR/$BACKUP_NAME"
        log_message "Backup completed successfully"
        
        rm -f "$BACKUP_DIR/$LATEST_LINK"
        ln -s "$BACKUP_NAME.qbkp.tar.gz" "$BACKUP_DIR/$LATEST_LINK"

        # Cleanup old backups
        cleanup_old_backups "$BACKUP_DIR" "$RETENTION_COUNT"

        end_time=$(date +%s)
        total_time=$((end_time - start_time))
        compression_time=$((compression_end_time - compression_start_time))
        backup_size=$(du -h "$BACKUP_DIR/$BACKUP_NAME.qbkp.tar.gz" | cut -f1)

        log_message "Backup statistics:"
        log_message "  Time taken for copying files: $((total_time - compression_time)) seconds"
        log_message "  Time taken for compression: $compression_time seconds"
        log_message "  Number of files backed up: $num_files"
        log_message "  Size of the final backup file: $backup_size"

        send_notification "Backup Completed Successfully" \
            "Files: $num_files
Size: $backup_size
Time: ${total_time}s (${compression_time}s compression)
Backup: $BACKUP_NAME.qbkp.tar.gz" \
            "default" \
            "white_check_mark,floppy_disk"
    else
        log_message "Error: Failed to create compressed archive"
        send_notification "Backup Failed" \
            "Failed to create compressed archive
Source: $SOURCE_DIR
Destination: $BACKUP_DIR" \
            "high" \
            "warning,floppy_disk"
        exit 1
    fi
else
    log_message "Error: Backup failed"
    send_notification "Backup Failed" \
        "Rsync operation failed
Source: $SOURCE_DIR
Destination: $BACKUP_DIR
Check logs: $LOG_FILE" \
        "high" \
        "warning,floppy_disk"
    rm -rf "$BACKUP_DIR/$BACKUP_NAME"
    exit 1
fi