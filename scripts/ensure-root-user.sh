#!/bin/bash
# Ensure MongoDB root user exists
# This script creates the root user if it doesn't exist (for existing databases)

set -e

MONGO_USERNAME=${MONGO_INITDB_ROOT_USERNAME}
MONGO_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD}
HOST=${1:-localhost}
PORT=${2:-27017}

if [ -z "$MONGO_USERNAME" ] || [ -z "$MONGO_PASSWORD" ]; then
  echo "Error: MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD must be set"
  exit 1
fi

echo "Checking if root user exists..."

# Try to connect and check if user exists
USER_EXISTS=$(mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --host "$HOST:$PORT" \
  --quiet \
  --eval "
    try {
      db.getSiblingDB('admin').getUser('$MONGO_USERNAME');
      print('EXISTS');
    } catch (e) {
      if (e.code === 11 || e.message.includes('not found')) {
        print('NOT_EXISTS');
      } else {
        throw e;
      }
    }
  " 2>/dev/null || echo "NOT_EXISTS")

if [ "$USER_EXISTS" = "EXISTS" ]; then
  echo "✓ Root user '$MONGO_USERNAME' already exists"
  exit 0
fi

echo "Root user not found. Creating root user..."

# Create the root user
mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --host "$HOST:$PORT" \
  --quiet \
  --eval "
    db.getSiblingDB('admin').createUser({
      user: '$MONGO_USERNAME',
      pwd: '$MONGO_PASSWORD',
      roles: [{ role: 'root', db: 'admin' }]
    });
    print('✓ Root user created successfully');
  " 2>&1

if [ $? -eq 0 ]; then
  echo "✓ Root user '$MONGO_USERNAME' created successfully"
else
  echo "✗ Failed to create root user"
  exit 1
fi
