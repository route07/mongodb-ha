#!/bin/bash
# MongoDB Replica Set Healthcheck Script
# Checks if mongod is running and if node is part of replica set
set -e

# First check if mongod process is running
if ! pgrep -x mongod > /dev/null; then
  exit 1
fi

# Try to connect and check replica set status
RS_STATUS=$(mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "${MONGO_INITDB_ROOT_USERNAME}" \
  -p "${MONGO_INITDB_ROOT_PASSWORD}" \
  --authenticationDatabase admin \
  --eval "try { rs.status().ok } catch(e) { 0 }" \
  --quiet 2>/dev/null || echo "0")

# If replica set is not initialized, that's okay for initial startup
# Just check if mongod is responding
if [ "$RS_STATUS" != "1" ]; then
  # Check basic connectivity
  mongosh --tls \
    --tlsAllowInvalidCertificates \
    --tlsCAFile /etc/mongo/ssl/ca.crt \
    -u "${MONGO_INITDB_ROOT_USERNAME}" \
    -p "${MONGO_INITDB_ROOT_PASSWORD}" \
    --authenticationDatabase admin \
    --eval "db.adminCommand('ping')" \
    --quiet \
    > /dev/null 2>&1
  exit $?
fi

# Replica set is initialized, check if this node is healthy
NODE_STATE=$(mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "${MONGO_INITDB_ROOT_USERNAME}" \
  -p "${MONGO_INITDB_ROOT_PASSWORD}" \
  --authenticationDatabase admin \
  --eval "rs.status().members.find(m => m.self === true)?.stateStr || 'UNKNOWN'" \
  --quiet 2>/dev/null || echo "UNKNOWN")

# Node is healthy if state is PRIMARY, SECONDARY, or ARBITER
if [[ "$NODE_STATE" =~ ^(PRIMARY|SECONDARY|ARBITER)$ ]]; then
  exit 0
else
  exit 1
fi
