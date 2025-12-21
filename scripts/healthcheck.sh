#!/bin/bash
# MongoDB healthcheck script
set -e

# First check if mongod process is running
if ! pgrep -x mongod > /dev/null; then
  exit 1
fi

# Try to connect with mongosh using TLS
# First try with authentication
if mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "${MONGO_INITDB_ROOT_USERNAME}" \
  -p "${MONGO_INITDB_ROOT_PASSWORD}" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  exit 0
fi

# If auth fails, try without auth (user might not exist yet)
# This allows the init-user container to create the user
if mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  # MongoDB is running but user doesn't exist - still healthy for init purposes
  exit 0
fi

# MongoDB is not responding
exit 1
