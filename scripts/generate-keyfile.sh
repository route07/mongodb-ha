#!/bin/bash

# Script to generate MongoDB keyFile for replica set authentication
# The keyFile is required when authorization is enabled with replica sets

set -e

KEYFILE_PATH="./tls-certs/keyfile"
KEYFILE_DIR="./tls-certs"

# Create tls-certs directory if it doesn't exist
mkdir -p "$KEYFILE_DIR"

# Check if keyfile already exists
if [ -f "$KEYFILE_PATH" ]; then
  echo "KeyFile already exists at $KEYFILE_PATH"
  echo "If you want to regenerate it, delete it first: rm $KEYFILE_PATH"
  exit 0
fi

echo "Generating MongoDB keyFile for replica set authentication..."

# Generate a random keyFile (base64 encoded, 756 characters = 567 bytes)
# MongoDB keyFile must be between 6 and 1024 characters
openssl rand -base64 567 > "$KEYFILE_PATH"

# Set proper permissions (must be readable by MongoDB user in container)
# MongoDB requires keyFile to have permissions 600 or less
# The entrypoint script will copy and fix permissions inside the container
chmod 600 "$KEYFILE_PATH"

echo "✓ KeyFile generated successfully at $KEYFILE_PATH"
echo ""
echo "Note: This keyFile is used for inter-node authentication in replica sets."
echo "Keep it secure and do not commit it to version control."
