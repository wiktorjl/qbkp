#!/bin/bash

# qbkp Cleanup Script
# Manually clean up old backup archives based on retention policy

CONFIG_FILE="$HOME/.qbkp/config"
DEFAULT_BACKUP_DIR="$HOME/.qbkp/data"
DEFAULT_RETENTION_COUNT=7
LOG_FILE="$HOME/.qbkp/log/cleanup.log"
DRY_RUN=false
MOVE_TO_TMP=false

# Source config if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
RETENTION_COUNT="${RETENTION_COUNT:-$DEFAULT_RETENTION_COUNT}"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --dry-run      Show what would be deleted without actually deleting"
    echo "  -m, --move-to-tmp  Move old backups to /tmp instead of deleting them"
    echo "  -d, --dir DIR      Backup directory (default: $DEFAULT_BACKUP_DIR)"
    echo "  -r, --retain NUM   Number of backups to retain (default: $DEFAULT_RETENTION_COUNT)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Clean up old backups (delete mode)"
    echo "  $0 --dry-run          # Show what would be deleted"
    echo "  $0 --move-to-tmp      # Move old backups to /tmp"
    echo "  $0 --retain 10        # Keep 10 most recent backups"
    exit 0
}

log_message() {
    local message="$1"
    mkdir -p "$(dirname "$LOG_FILE")"
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
    local dry_run="$3"
    local move_to_tmp="$4"

    cd "$backup_dir" || {
        log_message "Error: Cannot access backup directory: $backup_dir"
        send_notification "Cleanup Failed" \
            "Cannot access backup directory: $backup_dir" \
            "high" \
            "warning,broom"
        return 1
    }

    # Count only qbkp backup files
    local total_backups=$(ls -1 *.qbkp.tar.gz 2>/dev/null | wc -l)

    if [ "$total_backups" -eq 0 ]; then
        log_message "No qbkp backups found in $backup_dir"
        return 0
    fi

    log_message "Found $total_backups backup(s) in $backup_dir"

    # Calculate target: keep at least 2 backups, or retention_count if larger
    local target_remaining=$retention_count
    if [ "$target_remaining" -lt 2 ]; then
        target_remaining=2
        log_message "Adjusting retention to minimum of 2 backups"
    fi

    # Calculate how many to delete
    local to_delete=$((total_backups - target_remaining))

    if [ "$to_delete" -le 0 ]; then
        log_message "No cleanup needed. Current backups: $total_backups, Target: $target_remaining"
        return 0
    fi

    log_message "Will process $to_delete backup(s), keeping $target_remaining"

    # Get list of files to delete (oldest first, skipping the newest N)
    local files_to_delete=$(ls -t *.qbkp.tar.gz | tail -n "+$((target_remaining + 1))")

    if [ -z "$files_to_delete" ]; then
        log_message "No backups to delete after safety checks"
        return 0
    fi

    # Calculate space to be freed and perform cleanup
    local space_freed=0
    local deleted_count=0
    local tmp_dir=""

    if [ "$move_to_tmp" = true ]; then
        tmp_dir="/tmp/qbkp_cleanup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$tmp_dir"
        log_message "Created temporary directory: $tmp_dir"
    fi

    for file in $files_to_delete; do
        if [ ! -f "$file" ]; then
            log_message "Warning: File not found: $file"
            continue
        fi

        local file_size=$(du -b "$file" 2>/dev/null | cut -f1)
        space_freed=$((space_freed + file_size))
        deleted_count=$((deleted_count + 1))

        if [ "$dry_run" = true ]; then
            log_message "[DRY RUN] Would delete: $file ($(numfmt --to=iec-i --suffix=B $file_size 2>/dev/null || echo "$file_size bytes"))"
        elif [ "$move_to_tmp" = true ]; then
            if mv "$file" "$tmp_dir/"; then
                log_message "Moved to $tmp_dir: $file"
            else
                log_message "Error: Failed to move $file"
            fi
        else
            if rm -f "$file"; then
                log_message "Deleted: $file"
            else
                log_message "Error: Failed to delete $file"
            fi
        fi
    done

    # Convert bytes to human readable
    local space_freed_human=$(numfmt --to=iec-i --suffix=B $space_freed 2>/dev/null || echo "${space_freed} bytes")

    # Log cleanup summary
    log_message "=========================================="
    log_message "Cleanup Summary:"
    log_message "  Backups processed: $deleted_count"
    log_message "  Space freed: $space_freed_human"
    log_message "  Remaining backups: $((total_backups - deleted_count))"
    if [ "$move_to_tmp" = true ]; then
        log_message "  Files moved to: $tmp_dir"
    fi
    log_message "=========================================="

    # Send notification
    local action="Deleted"
    local extra_info=""
    if [ "$dry_run" = true ]; then
        action="Would delete"
    elif [ "$move_to_tmp" = true ]; then
        action="Moved to /tmp"
        extra_info="
Location: $tmp_dir"
    fi

    send_notification "Backup Cleanup Completed" \
        "$action: $deleted_count backup(s)
Space freed: $space_freed_human
Remaining: $((total_backups - deleted_count)) backup(s)${extra_info}" \
        "default" \
        "broom,floppy_disk"

    return 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -m|--move-to-tmp)
            MOVE_TO_TMP=true
            shift
            ;;
        -d|--dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -r|--retain)
            RETENTION_COUNT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1"
            echo ""
            usage
            ;;
    esac
done

# Validate retention count
if ! [[ "$RETENTION_COUNT" =~ ^[0-9]+$ ]] || [ "$RETENTION_COUNT" -lt 1 ]; then
    log_message "Error: Invalid retention count: $RETENTION_COUNT"
    echo "Error: Retention count must be a positive integer"
    exit 1
fi

# Check if both dry-run and move-to-tmp are specified
if [ "$DRY_RUN" = true ] && [ "$MOVE_TO_TMP" = true ]; then
    log_message "Error: Cannot use --dry-run and --move-to-tmp together"
    echo "Error: --dry-run and --move-to-tmp are mutually exclusive"
    exit 1
fi

# Verify backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    log_message "Error: Backup directory does not exist: $BACKUP_DIR"
    echo "Error: Backup directory does not exist: $BACKUP_DIR"
    exit 1
fi

# Display configuration
log_message "=========================================="
log_message "qbkp Cleanup Starting"
log_message "  Backup directory: $BACKUP_DIR"
log_message "  Retention count: $RETENTION_COUNT"
log_message "  Dry run mode: $DRY_RUN"
log_message "  Move to /tmp: $MOVE_TO_TMP"
log_message "=========================================="

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "=== DRY RUN MODE ==="
    echo "No files will be deleted. This is a simulation."
    echo ""
fi

# Perform cleanup
cleanup_old_backups "$BACKUP_DIR" "$RETENTION_COUNT" "$DRY_RUN" "$MOVE_TO_TMP"
exit_code=$?

if [ $exit_code -eq 0 ]; then
    log_message "Cleanup completed successfully"
else
    log_message "Cleanup completed with errors"
    send_notification "Cleanup Failed" \
        "Cleanup operation encountered errors
Check logs: $LOG_FILE" \
        "high" \
        "warning,broom"
fi

exit $exit_code
