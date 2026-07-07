#!/bin/sh
# Change root password for the camera
# Usage: passwd.sh [new_password]
# If no password provided, prompts interactively

PASSWD_FILE="/system/sdcard/etc/shadow"

if [ $# -eq 1 ]; then
  NEW_PASS="$1"
else
  echo -n "Enter new password: "
  read -s NEW_PASS
  echo
  echo -n "Confirm new password: "
  read -s CONFIRM_PASS
  echo
  if [ "$NEW_PASS" != "$CONFIRM_PASS" ]; then
    echo "ERROR: Passwords do not match"
    exit 1
  fi
fi

if [ -z "$NEW_PASS" ]; then
  echo "ERROR: Password cannot be empty"
  exit 1
fi

# Generate password hash using busybox
HASH=$( busybox passwd -m "$NEW_PASS" 2>/dev/null | grep -oE ':[^:]+:' | head -1 | tr -d ':')

if [ -z "$HASH" ]; then
  # Fallback: use openssl if available
  if [ -x /system/sdcard/bin/openssl ]; then
    HASH=$( /system/sdcard/bin/openssl passwd -1 -salt "$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')" "$NEW_PASS" 2>/dev/null )
  fi
fi

if [ -z "$HASH" ]; then
  echo "ERROR: Could not generate password hash"
  exit 1
fi

# Update shadow file
if [ -f "$PASSWD_FILE" ]; then
  sed -i "s|^root:[^:]*:|root:$HASH:|" "$PASSWD_FILE"
  echo "Password updated successfully"
  echo "Shadow file: $PASSWD_FILE"
else
  echo "ERROR: Shadow file not found at $PASSWD_FILE"
  exit 1
fi
