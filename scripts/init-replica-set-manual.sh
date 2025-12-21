#!/bin/bash
# Manually initialize replica set
# Use this if the automatic init container fails

set -e

if [ ! -f .env ]; then
  echo "Error: .env file not found"
  exit 1
fi

export $(grep -v '^#' .env | xargs)

if [ -z "$MONGO_INITDB_ROOT_USERNAME" ] || [ -z "$MONGO_INITDB_ROOT_PASSWORD" ]; then
  echo "Error: MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD must be set in .env"
  exit 1
fi

REPLICA_SET_NAME=${REPLICA_SET_NAME:-rs0}

echo "=========================================="
echo "Manual Replica Set Initialization"
echo "=========================================="
echo ""
echo "Replica Set Name: $REPLICA_SET_NAME"
echo "Username: $MONGO_INITDB_ROOT_USERNAME"
echo ""

# Check if replica set is already initialized
echo "Checking if replica set is already initialized..."
RS_STATUS=$(docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "try { rs.status().ok } catch(e) { 0 }" \
  --quiet 2>/dev/null || echo "0")

if [ "$RS_STATUS" = "1" ]; then
  echo "✓ Replica set '$REPLICA_SET_NAME' is already initialized"
  docker exec mongo-primary mongosh --tls \
    --tlsAllowInvalidCertificates \
    --tlsCAFile /etc/mongo/ssl/ca.crt \
    -u "$MONGO_INITDB_ROOT_USERNAME" \
    -p "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))" \
    --quiet
  exit 0
fi

echo "Replica set not initialized. Initializing..."
echo ""

# Initialize replica set
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    rs.initiate({
      _id: '$REPLICA_SET_NAME',
      members: [
        { _id: 0, host: 'mongodb-primary:27017', priority: 2 },
        { _id: 1, host: 'mongodb-secondary-1:27017', priority: 1 },
        { _id: 2, host: 'mongodb-secondary-2:27017', priority: 1 }
      ]
    })
  " 2>&1

echo ""
echo "Waiting for replica set to stabilize (10 seconds)..."
sleep 10

# Check status
echo ""
echo "Replica Set Status:"
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    const status = rs.status();
    print('Replica Set: ' + status.set);
    print('Primary: ' + (status.members.find(m => m.stateStr === 'PRIMARY')?.name || 'None'));
    print('Members:');
    status.members.forEach(m => {
      print('  - ' + m.name + ': ' + m.stateStr + ' (health: ' + m.health + ')');
    });
  " \
  --quiet

echo ""
echo "✓ Replica set '$REPLICA_SET_NAME' initialized successfully!"
