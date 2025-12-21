#!/bin/bash
# Fix keyfile permissions inside container
# MongoDB requires keyfile to be readable by the mongod process (UID 999)

set -e

SOURCE_KEYFILE="/etc/mongo/ssl/keyfile"
KEYFILE_PATH="/data/keyfile"

if [ -f "$SOURCE_KEYFILE" ]; then
  # Copy keyfile to writable location and remove trailing newlines
  tr -d '\n' < "$SOURCE_KEYFILE" > "$KEYFILE_PATH"
  
  # Set permissions to 600 (MongoDB requirement)
  chmod 600 "$KEYFILE_PATH"
  
  # Change ownership to mongodb user (UID 999)
  chown 999:999 "$KEYFILE_PATH"
  
  echo "✓ Keyfile copied and permissions fixed at $KEYFILE_PATH"
else
  echo "⚠ Keyfile not found at $SOURCE_KEYFILE"
  exit 1
fi

# Execute the original command, replacing keyfile path in arguments
# Convert all arguments to array, replace keyfile path, then execute
ARGS=("$@")
for i in "${!ARGS[@]}"; do
  if [[ "${ARGS[$i]}" == "--keyFile" ]] && [[ "${ARGS[$i+1]}" == "/etc/mongo/ssl/keyfile" ]]; then
    ARGS[$i+1]="$KEYFILE_PATH"
  fi
done

exec "${ARGS[@]}"
