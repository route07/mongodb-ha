#!/bin/bash
# Script to fix replica set after restart

echo "=========================================="
echo "Fixing MongoDB Replica Set"
echo "=========================================="
echo ""

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found. Make sure you're in the ha-mongodb directory."
    exit 1
fi

# Source .env
source .env

# Check if required variables are set
if [ -z "$MONGO_INITDB_ROOT_USERNAME" ] || [ -z "$MONGO_INITDB_ROOT_PASSWORD" ]; then
    echo "⚠️  MONGO_INITDB_ROOT_USERNAME or MONGO_INITDB_ROOT_PASSWORD not set in .env"
    exit 1
fi

REPLICA_SET_NAME=${REPLICA_SET_NAME:-rs0}

echo "Step 1: Checking current status..."
echo "-------------------------------------------"
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var status = rs.status();
      var primary = status.members.find(m => m.stateStr === 'PRIMARY');
      if (primary) {
        print('✅ Primary found: ' + primary.name);
        print('   Replica set is healthy. No action needed.');
        exit(0);
      } else {
        print('⚠️  No primary found. Attempting to fix...');
      }
    } catch(e) {
      if (e.message.includes('no replset config')) {
        print('⚠️  Replica set not initialized. Will initialize...');
      } else {
        print('Error checking status: ' + e.message);
      }
    }
  " 2>/dev/null

echo ""
echo "Step 2: Attempting to fix..."
echo "-------------------------------------------"

# Try to initialize or re-elect
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      // Check if initialized
      var status = rs.status();
      
      // Try to step down current primary (if any) to force re-election
      try {
        rs.stepDown(60);
        print('Stepped down current primary. Waiting for re-election...');
      } catch(e) {
        // No primary to step down, or already stepped down
        print('No primary to step down');
      }
    } catch(e) {
      // Replica set not initialized
      if (e.message.includes('no replset config')) {
        print('Initializing replica set...');
        rs.initiate({
          _id: '$REPLICA_SET_NAME',
          members: [
            { _id: 0, host: 'mongodb-primary:27017', priority: 2 },
            { _id: 1, host: 'mongodb-secondary-1:27017', priority: 1 },
            { _id: 2, host: 'mongodb-secondary-2:27017', priority: 1 }
          ]
        });
        print('✅ Replica set initialized');
      } else {
        print('Error: ' + e.message);
      }
    }
  " 2>/dev/null

echo ""
echo "Step 3: Waiting for primary election (30 seconds)..."
echo "-------------------------------------------"
sleep 30

echo ""
echo "Step 4: Checking final status..."
echo "-------------------------------------------"
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var status = rs.status();
      var primary = status.members.find(m => m.stateStr === 'PRIMARY');
      if (primary) {
        print('✅ SUCCESS! Primary is now: ' + primary.name);
      } else {
        print('⚠️  Still no primary. This may take more time.');
        print('   Run this script again in 30 seconds, or check:');
        print('   ./scripts/check-replica-set-status.sh');
      }
    } catch(e) {
      print('Error: ' + e.message);
    }
  " 2>/dev/null

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
