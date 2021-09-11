#!/usr/bin/env bash

# Created by Jeff Shepherd (https://hummdis.com).

#   .------..------..------..------..------..------..------.
#   |H.--. ||U.--. ||M.--. ||M.--. ||D.--. ||I.--. ||S.--. |
#   | :/\: || (\/) || (\/) || (\/) || :/\: || (\/) || :/\: |
#   | (__) || :\/: || :\/: || :\/: || (__) || :\/: || :\/: |
#   | '--'H|| '--'U|| '--'M|| '--'M|| '--'D|| '--'I|| '--'S|
#   `------'`------'`------'`------'`------'`------'`------'

# Apply all security patches for RHEL systems up to a given date.
# All events logged to /var/log/security_updates.log

VERSION="0.1.0"

CHECK_DATE="$1"
FULL_UPDATE_LIST="/tmp/fullupdatelist.txt"
UPDATE_LIST="/tmp/updatelist.txt"
LOG_FILE="/var/log/security_updates.log"
UPDATES_TODO=()

# For security, limit which vars can be changed.
readonly CHECK_DATE
readonly FULL_UPDATE_LIST
readonly UPDATE_LIST

# Validate the date given.
validate_date() {
    declare -i DAY
    
    #shellcheck disable=SC2046,SC2001
    eval $(echo "$CHECK_DATE" | sed 's/^\(....\)-\(..\)-\(..\)/YEAR=\1 MONTH=\2 DAY=\3/')

    if ! cal "$MONTH" "$YEAR" 2> /dev/null | grep -w "$DAY" > /dev/null; then
        help_text
        exit 67
    fi

    # OK, the date is valid, but is it in the future?
    CHK_DATE=$(date -d "$CHECK_DATE" +%s)
    TODAY=$(date +%s)
    if [ "$CHK_DATE" -gt "$TODAY" ]; then
        help_text
        exit 68
    fi
}

# For consistent log entries.
echo_log() {
    TIMESTAMP=$(date +%F\ %H:%M:%S)
    echo "$TIMESTAMP: $1" >> "$LOG_FILE"
}

# Help Text
help_text() {
    echo "ERROR: Invalid 'date' provided.
$0 <date>

Date must be in YYYY-MM-DD format (ISO-8601 standard) and not be in the future.
Eg: $0 2019-12-25"
}

generate_list() {
# First, get a list of the security updates available (not installed).
    echo_log "Generating list of uninstalled security advisories..."
    if grep -q grep "VERSION_ID=7" /etc/os-release; then
        yum updateinfo info security | grep -E "Update ID :|Issued :" >> $FULL_UPDATE_LIST
    elif grep -q grep "VERSION_ID=8" /etc/os-release; then
        yum updateinfo info security | grep -E "Update ID:|Updated:" >> $FULL_UPDATE_LIST
    else
        echo "Failed to determine which RHEL relase.  Modify lines 56-63 to support your OS or submit an issue at GitHub."
        echo "Be sure to include the full results of 'cat /etc/os-release' so it can be fixed."
        exit 69
    fi
    while mapfile -t -n 2 ary && ((${#ary[@]})); do
        printf '%s\t' "${ary[@]}" >> $UPDATE_LIST
        printf -- '\n' >> $UPDATE_LIST
    done < $FULL_UPDATE_LIST
}

processing() {
    # Next, get the details for each, looking for the provided date.
    echo_log "Reading full advisory list..."
    OLD_IFS="$IFS"
    while IFS= read -r LINE; do
        UPDATE_ID=$(echo "$LINE" | awk '{print $3}')
        UPDATE_DATE=$(echo "$LINE" | awk '{print $5}')

        # Before we compare dates, convert the dates to a Unix timestamp, then
        # compare them.
        CHK_DATE=$(date -d "$CHECK_DATE" +%s)
        UPD_DATE=$(date -d "$UPDATE_DATE" +%s)
        #shellcheck disable=SC2086
        if [ $UPD_DATE -le $CHK_DATE ]; then
            echo_log "Adding security advisory $UPDATE_ID to To Do list..."
            UPDATES_TODO+=("$UPDATE_ID")
        else
            echo_log "WARNING: Skipping Advisory ID $UPDATE_ID is newer than $CHECK_DATE."
            echo_log "         Date of $UPDATE_ID is $UPDATE_DATE"
        fi
    done < "$UPDATE_LIST"
    IFS="$OLD_IFS"
}

do_updates() {
    # Make sure we've actually got work to do...
    if [ ${#UPDATES_TODO[@]} -eq 0 ]; then
        echo_log "No updates match required date. Nothing to do."
        cleanup
        # Just because there's nothing to do doesn't mean there's an error.
        exit 0
    fi

    # We've got our update list, now do the updates.
    echo_log "Starting install of security advisories..."
    for UPDATE in "${UPDATES_TODO[@]}"; do
        echo_log "Starting installation of $UPDATE..."
        yum -q -y update --advisory="$UPDATE"
    done
    echo_log "Installation process completed."
}

cleanup() {
    # Cleanup
    echo_log "Cleaning up."
    rm -f "$FULL_UPDATE_LIST" "$UPDATE_LIST"
}

# Do it in the order we say.
echo "YUM Update By Date v$VERSION"
validate_date
generate_list
processing
do_updates
cleanup

exit 0