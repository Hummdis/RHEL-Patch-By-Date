#!/bin/bash

# Created by Jeff Shepherd (https://hummdis.com).

#   .------..------..------..------..------..------..------.
#   |H.--. ||U.--. ||M.--. ||M.--. ||D.--. ||I.--. ||S.--. |
#   | :/\: || (\/) || (\/) || (\/) || :/\: || (\/) || :/\: |
#   | (__) || :\/: || :\/: || :\/: || (__) || :\/: || :\/: |
#   | '--'H|| '--'U|| '--'M|| '--'M|| '--'D|| '--'I|| '--'S|
#   `------'`------'`------'`------'`------'`------'`------'

# Apply all security patches for RHEL systems up to a given date.
# All events logged to /var/log/security_updates.log

VERSION="0.2.0"

CHECK_DATE="$1"
FULL_UPDATE_LIST="/tmp/fullupdatelist.txt"
UPDATE_LIST="/tmp/updatelist.txt"
LOG_FILE="/var/log/security_updates.log"
UPDATES_TODO=()

# For security, limit which vars can be changed.
readonly CHECK_DATE FULL_UPDATE_LIST UPDATE_LIST LOG_FILE

function validate_date() {
  # Validate the date given.
  declare -i DAY
  
  #shellcheck disable=SC2046,SC2001
  eval $(echo "$CHECK_DATE" | /usr/bin/sed 's/^\(....\)-\(..\)-\(..\)/YEAR=\1 MONTH=\2 DAY=\3/')

  if ! /usr/bin/cal "$MONTH" "$YEAR" 2> /dev/null | \
    /usr/bin/grep -w "$DAY" > /dev/null; then
    help_text
    exit 67
  fi

  # OK, the date is valid, but is it in the future?
  CHK_DATE=$(/usr/bin/date -d "$CHECK_DATE" +%s)
  TODAY=$(/usr/bin/date +%s)
  if [ "$CHK_DATE" -gt "$TODAY" ]; then
    help_text
    exit 68
  fi
}

function echo_log() {
  # For consistent log entries.
  TIMESTAMP=$(/usr/bin/date +%F\ %H:%M:%S)
  echo "$TIMESTAMP: $1" >> "$LOG_FILE"
}

function help_text() {
  # Display Help Text
  echo "
================================================================================
  RHEL Update by Date Script - v$VERSION - github.com/Hummdis/RHEL-Patch-By-Date
================================================================================

Description: Use this script to apply security updates via YUM up to the date
provided by the argument passed.

Usage: $0 <date>

Options:
  -h | --help | help - Display this help text.

Date must be in YYYY-MM-DD format (ISO-8601 standard) and not be in the future.
i.e.: $0 2019-12-25
"
}

function check_os_ver() {
  if /usr/bin/grep -q 'VERSION_ID="7' /etc/os-release; then
    RHEL_VER="7"
  elif /usr/bin/grep -q 'VERSION_ID="8' /etc/os-release; then
    RHEL_VER="8"
  else
    bad_rhel_version
  fi
  readonly RHEL_VER
}

function generate_list() {
  # First, get a list of the security updates available (not installed).
  echo_log "Generating list of uninstalled security advisories..."
  touch $FULL_UPDATE_LIST
  touch $UPDATE_LIST
  case "$RHEL_VER" in
    7) 
      /usr/bin/yum updateinfo info security | \
        /usr/bin/grep -E "Update ID :|Issued :" >> $FULL_UPDATE_LIST
      ;;
    8) 
      /usr/bin/yum updateinfo info security | \
        /usr/bin/grep -E "Update ID:|Updated:" >> $FULL_UPDATE_LIST
      ;;
    *)
      bad_rhel_version
      ;;
  esac

  while mapfile -t -n 2 ary && ((${#ary[@]})); do
    /usr/bin/printf '%s\t' "${ary[@]}" >> $UPDATE_LIST
    /usr/bin/printf -- '\n' >> $UPDATE_LIST
  done < $FULL_UPDATE_LIST
}

function processing() {
  # Next, get the details for each, looking for the provided date.
  echo_log "Reading full advisory list..."
  OLD_IFS="$IFS"
  while IFS= read -r LINE; do
    case "$RHEL_VER" in
      7)
        UPDATE_ID=$(echo "$LINE" | /usr/bin/awk '{print $4}')
        UPDATE_DATE=$(echo "$LINE" | /usr/bin/awk '{print $7}')
        ;;
      8)
        UPDATE_ID=$(echo "$LINE" | /usr/bin/awk '{print $3}')
        UPDATE_DATE=$(echo "$LINE" | /usr/bin/awk '{print $5}')
        ;;
      *)
        bad_rhel_version
        ;;
    esac

    # Before we compare dates, convert the dates to a Unix timestamp, then
    # compare them.
    CHK_DATE=$(/usr/bin/date -d "$CHECK_DATE" +%s)
    UPD_DATE=$(/usr/bin/date -d "$UPDATE_DATE" +%s)

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

function do_updates() {
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
    if ! /usr/bin/yum -q -y update --advisory="$UPDATE"; then
      echo $'\u26D4' "Installation of update $UPDATE failed."
      echo "Run manually to see all errors. Aborting."
      exit 66
    fi
    echo_log "Installation of $UPDATE complete."
  done
  echo_log "Installation process completed."
}

function cleanup() {
  # Cleanup
  echo_log "Cleaning up."
  /usr/bin/rm -f "$FULL_UPDATE_LIST" "$UPDATE_LIST"
}

function bad_rhel_version() {
  # This function is executed if the version of RHEL is not 7 or 8.  Other
  # versions are not going to work as-is.  Modifications to this script are
  # going to be needed.
  echo "This version of RHEL is not supported by this script as-is."
  echo "Modifications are needed. Aborting."
  exit 69
}

# Make sure the username argument is not blank.
case "$CHECK_DATE" in
  "-h"|"--help"|"help"|"")
    help_text
    exit 67
    ;;
  *)
    # Continue.
    ;;
esac

function main() {
  # Do it in the order we say.
  validate_date
  check_os_ver
  generate_list
  processing
  do_updates
  cleanup
}

# Make sure we get our proxy info, if it's needed.
#shellcheck disable=SC1091
. /etc/profile.d/proxy.sh


if [ "$EUID" -ne 0 ]; then
  echo $'\u26D4' "You must be root to run this script."
  exit 67
fi


main

exit 0