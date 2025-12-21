#!/bin/bash
# Replica Set Initialization Script
# This script initializes the MongoDB replica set

set -e

REPLICA_SET_NAME=${REPLICA_SET_NAME:-rs0}
MONGO_USERNAME=${MONGO_INITDB_ROOT_USERNAME}
MONGO_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD}
PRIMARY_HOST="mongodb-primary"
SECONDARY1_HOST="mongodb-secondary-1"
SECONDARY2_HOST="mongodb-secondary-2"
PORT=27017

echo "Waiting for MongoDB nodes to be ready..."
sleep 5

# Function to check if MongoDB is ready
wait_for_mongo() {
  local host=$1
  local max_attempts=30
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    if mongosh --tls \
      --tlsAllowInvalidCertificates \
      --tlsCAFile /etc/mongo/ssl/ca.crt \
      -u "$MONGO_USERNAME" \
      -p "$MONGO_PASSWORD" \
      --authenticationDatabase admin \
      --host "$host:$PORT" \
      --eval "db.adminCommand('ping')" \
      --quiet > /dev/null 2>&1; then
      echo "✓ $host is ready"
      return 0
    fi
    attempt=$((attempt + 1))
    echo "Waiting for $host... (attempt $attempt/$max_attempts)"
    sleep 2
  done
  
  echo "✗ $host failed to become ready"
  return 1
}

# Wait for all nodes
wait_for_mongo "$PRIMARY_HOST"
wait_for_mongo "$SECONDARY1_HOST"
wait_for_mongo "$SECONDARY2_HOST"

echo "All MongoDB nodes are ready. Initializing replica set..."

# Check if replica set is already initialized
RS_STATUS=$(mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_USERNAME" \
  -p "$MONGO_PASSWORD" \
  --authenticationDatabase admin \
  --host "$PRIMARY_HOST:$PORT" \
  --eval "rs.status().ok" \
  --quiet 2>/dev/null || echo "0")

if [ "$RS_STATUS" = "1" ]; then
  echo "Replica set '$REPLICA_SET_NAME' is already initialized."
  echo "Current status:"
  mongosh --tls \
    --tlsAllowInvalidCertificates \
    --tlsCAFile /etc/mongo/ssl/ca.crt \
    -u "$MONGO_USERNAME" \
    -p "$MONGO_PASSWORD" \
    --authenticationDatabase admin \
    --host "$PRIMARY_HOST:$PORT" \
    --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))" \
    --quiet
  exit 0
fi

# Initialize replica set
echo "Initializing replica set '$REPLICA_SET_NAME'..."

mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_USERNAME" \
  -p "$MONGO_PASSWORD" \
  --authenticationDatabase admin \
  --host "$PRIMARY_HOST:$PORT" \
  --eval "
    rs.initiate({
      _id: '$REPLICA_SET_NAME',
      members: [
        { _id: 0, host: '$PRIMARY_HOST:$PORT', priority: 2 },
        { _id: 1, host: '$SECONDARY1_HOST:$PORT', priority: 1 },
        { _id: 2, host: '$SECONDARY2_HOST:$PORT', priority: 1 }
      ]
    })
  " \
  --quiet

echo "Waiting for replica set to stabilize..."
sleep 10

# Wait for primary to be elected
echo "Waiting for primary election..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
  PRIMARY_STATE=$(mongosh --tls \
    --tlsAllowInvalidCertificates \
    --tlsCAFile /etc/mongo/ssl/ca.crt \
    -u "$MONGO_USERNAME" \
    -p "$MONGO_PASSWORD" \
    --authenticationDatabase admin \
    --host "$PRIMARY_HOST:$PORT" \
    --eval "rs.isMaster().ismaster" \
    --quiet 2>/dev/null || echo "false")
  
  if [ "$PRIMARY_STATE" = "true" ]; then
    echo "✓ Primary node elected: $PRIMARY_HOST"
    break
  fi
  attempt=$((attempt + 1))
  sleep 2
done

# Display replica set status
echo ""
echo "Replica Set Status:"
echo "==================="
mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_USERNAME" \
  -p "$MONGO_PASSWORD" \
  --authenticationDatabase admin \
  --host "$PRIMARY_HOST:$PORT" \
  --eval "
    const status = rs.status();
    print('Replica Set: ' + status.set);
    print('Primary: ' + status.members.find(m => m.stateStr === 'PRIMARY')?.name || 'None');
    print('Members:');
    status.members.forEach(m => {
      print('  - ' + m.name + ': ' + m.stateStr + ' (health: ' + m.health + ')');
    });
  " \
  --quiet

echo ""
echo "✓ Replica set '$REPLICA_SET_NAME' initialized successfully!"
