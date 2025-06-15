#!/bin/bash
SCRIPT_VERSION="1.1.0"
# Load config
CONFIG_FILE="/etc/weekly_maintenance.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi

TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

check_update_and_restart() {
    echo "Checking for updates..."

    # Clone the repository
    git clone --depth=1 --branch "$REMOTE_BRANCH" "$GIT_REPO_URL" "$TMP_DIR" >/dev/null 2>&1 || {
        echo "Failed to clone repo"
        return 1
    }

    # Extract remote version
    REMOTE_VERSION=$(grep "^SCRIPT_VERSION=" "$TMP_DIR/$SCRIPT_NAME" | cut -d'=' -f2 | tr -d '"')

    if [[ "$REMOTE_VERSION" != "$SCRIPT_VERSION" ]]; then
        echo "New version found: $REMOTE_VERSION (current: $SCRIPT_VERSION)"
        
        cp "$TMP_DIR/$SCRIPT_NAME" "$(realpath "$0")"
        echo "Updated script. Restarting..."
        exec bash "$(realpath "$0")" "$@"
    else
        echo "No update needed. Current version: $SCRIPT_VERSION"
    fi
}

if [[ "$AUTO_UPDATE" == "true" ]]; then
    check_update_and_restart "$@"
fi

################################################################################################
# Weekly Maintenance Script for Debian 12+
# Also known to work with ubuntu 22.10

# Validate required config variables
if [[ -z "$WEBHOOK_URL" ]]; then
    echo "ERROR: WEBHOOK_URL is not defined in $CONFIG_FILE"
    exit 1
fi

# Variables
LOG_FILE="/var/log/weekly_maintenance.log"
HOSTNAME=$(hostname)
STATUS="Pass"
FAILED_TASK=""
ERROR_MSG=""
TASKS_LEFT=()
TIMESTAMP="$(date '+%Y%m%d-%H%M')"

# Function to log messages
log() {
    echo "$(date '+%Y%m%d-%H:%M:%S') $*" >> "$LOG_FILE"
}

# Function to send POST request
send_post() {
    local status="$1"
    local failed_task="$2"
    local error_msg="$3"
    local tasks_left="$4"

    local post_data="{\"Node\": \"${HOSTNAME}\", \"Status\": \"${status}\""

    if [[ "$status" == "Fail" ]]; then
        post_data+=", \"FailedTask\": \"${failed_task}\", \"Error\": \"${error_msg}\", \"TasksLeft\": \"${tasks_left}\""
    fi

    post_data+="}"

    log "Sending POST: $post_data"

    curl -s -X POST -H "Content-Type: application/json" -d "$post_data" "$WEBHOOK_URL"
    if [[ $? -ne 0 ]]; then
        log "ERROR: Failed to send POST request"
    fi
}

# Function to run a task with error handling
run_task() {
    local task_name="$1"
    local command="$2"

    log "Running task: $task_name"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would run: $command"
    else
        eval "$command"
        if [[ $? -ne 0 ]]; then
            STATUS="Fail"
            FAILED_TASK="$task_name"
            ERROR_MSG="Command failed: $command"
            send_post "$STATUS" "$FAILED_TASK" "$ERROR_MSG" "${TASKS_LEFT[*]}"
            exit 1
        fi
    fi

    log "Task completed: $task_name"
}

# Disk space check
check_disk_space() {
    log "Checking disk space threshold ($DISK_THRESHOLD%)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would check disk space"
        return
    fi

    while read -r line; do
        usage_percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount_point=$(echo "$line" | awk '{print $6}')
        if [[ "$usage_percent" -ge "$DISK_THRESHOLD" ]]; then
            STATUS="Fail"
            FAILED_TASK="Disk Space Check"
            ERROR_MSG="Disk usage on $mount_point is ${usage_percent}%"
            send_post "$STATUS" "$FAILED_TASK" "$ERROR_MSG" "${TASKS_LEFT[*]}"
            exit 1
        fi
    done < <(df -hP | grep -vE '^Filesystem|tmpfs|cdrom')
    
    log "Disk space check passed"
}

# Check if reboot is needed
check_reboot_needed() {
    local reboot_needed=false

    if [[ -f /var/run/reboot-required ]]; then
        reboot_needed=true
    fi

    local uptime_days
    uptime_days=$(awk '{print int($1/86400)}' /proc/uptime)
    if [[ $uptime_days -gt 28 ]]; then
        reboot_needed=true
    fi

    if $reboot_needed; then
        log "Reboot required. Uptime=${uptime_days} days."

        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would reboot the system"
        else
            send_post "Pass" "" "" ""  # Send success before reboot
            log "Rebooting system..."
            reboot
            exit 0
        fi
    else
        log "No reboot needed. Uptime=${uptime_days} days."
    fi
}

# Define tasks
TASKS=(
    "APT Update"
    "APT Upgrade"
    "APT Autoremove"
    "APT Autoclean"
    "Disk Space Check"
    "Check Failed Services"
    "Check Reboot Needed"
)

# Start maintenance
log "=== Starting weekly maintenance ($TIMESTAMP) ==="

for task in "${TASKS[@]}"; do
    TASKS_LEFT=("${TASKS[@]}")
    TASKS_LEFT=("${TASKS_LEFT[@]:$((${#TASKS[@]} - ${#TASKS_LEFT[@]}))}")

    case "$task" in
        "APT Update")
            run_task "$task" "apt update -y"
            ;;
        "APT Upgrade")
            run_task "$task" "DEBIAN_FRONTEND=noninteractive apt upgrade -y"
            ;;
        "APT Autoremove")
            run_task "$task" "apt autoremove -y"
            ;;
        "APT Autoclean")
            run_task "$task" "apt autoclean -y"
            ;;
        "Disk Space Check")
            check_disk_space
            ;;
        "Check Failed Services")
            run_task "$task" "systemctl --failed --quiet"
            ;;
        "Check Reboot Needed")
            check_reboot_needed
            ;;
        *)
            log "Unknown task: $task"
            ;;
    esac
done

# Final success POST
send_post "$STATUS" "" "" ""

log "=== Weekly maintenance completed successfully ($TIMESTAMP) ==="
exit 0
