#!/bin/bash
# Script to add a MongoDB peer to the replica set
# Usage: ./scripts/add-mongo-peer.sh <hostname:port> [priority]
# Example: ./scripts/add-mongo-peer.sh mongodb-secondary-2:27017
#          ./scripts/add-mongo-peer.sh mongodb-secondary-2:27017 1
#          ./scripts/add-mongo-peer.sh new-server.example.com:27017 1

set -e

echo "=========================================="
echo "Add MongoDB Peer to Replica Set"
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

# Check if peer hostname is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <hostname:port> [priority]"
    echo ""
    echo "Examples:"
    echo "  $0 mongodb-secondary-2:27017"
    echo "  $0 mongodb-secondary-2:27017 1"
    echo "  $0 new-server.example.com:27017 1"
    echo ""
    echo "Arguments:"
    echo "  hostname:port  - Full hostname and port of the MongoDB instance to add"
    echo "  priority       - Optional priority (default: 1, higher = more likely to become primary)"
    echo ""
    echo "Current replica set members:"
    echo "-------------------------------------------"
    # Try to find any running MongoDB container to show status
    MONGO_CONTAINER=""
    for container in mongo-primary mongodb-secondary-1 mongodb-secondary-2; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            MONGO_CONTAINER="$container"
            break
        fi
    done
    
    if [ -n "$MONGO_CONTAINER" ]; then
        docker exec "$MONGO_CONTAINER" mongosh --tls \
          --tlsAllowInvalidCertificates \
          --tlsCAFile /etc/mongo/ssl/ca.crt \
          -u "$MONGO_INITDB_ROOT_USERNAME" \
          -p "$MONGO_INITDB_ROOT_PASSWORD" \
          --authenticationDatabase admin \
          --quiet \
          --eval "
            try {
              var status = rs.status();
              status.members.forEach(function(m) {
                var priority = m.priority !== undefined ? m.priority : 1;
                print('  ' + m.name + ': ' + m.stateStr + ' (priority: ' + priority + ')');
              });
            } catch(e) {
              print('  Error: ' + e.message);
            }
          " 2>/dev/null || echo "  Could not connect to replica set"
    else
        echo "  No MongoDB containers running"
    fi
    exit 1
fi

PEER_TO_ADD="$1"
PRIORITY=${2:-1}
REPLICA_SET_NAME=${REPLICA_SET_NAME:-rs0}
PORT=27017

# Normalize peer hostname (add port if not present)
if [[ ! "$PEER_TO_ADD" == *":"* ]]; then
    PEER_TO_ADD="${PEER_TO_ADD}:${PORT}"
fi

echo "Target peer to add: $PEER_TO_ADD"
echo "Priority: $PRIORITY"
echo ""

# Find primary container
echo "1. Finding primary MongoDB node..."
echo "-------------------------------------------"
MONGO_CONTAINER=""
PRIMARY_HOST=""
for container in mongo-primary mongodb-secondary-1 mongodb-secondary-2; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        # Check if this is the primary
        IS_PRIMARY=$(docker exec "$container" mongosh --tls \
          --tlsAllowInvalidCertificates \
          --tlsCAFile /etc/mongo/ssl/ca.crt \
          -u "$MONGO_INITDB_ROOT_USERNAME" \
          -p "$MONGO_INITDB_ROOT_PASSWORD" \
          --authenticationDatabase admin \
          --quiet \
          --eval "rs.isMaster().ismaster" 2>/dev/null || echo "false")
        
        if [ "$IS_PRIMARY" = "true" ]; then
            MONGO_CONTAINER="$container"
            PRIMARY_HOST=$(docker exec "$container" mongosh --tls \
              --tlsAllowInvalidCertificates \
              --tlsCAFile /etc/mongo/ssl/ca.crt \
              -u "$MONGO_INITDB_ROOT_USERNAME" \
              -p "$MONGO_INITDB_ROOT_PASSWORD" \
              --authenticationDatabase admin \
              --quiet \
              --eval "rs.isMaster().me" 2>/dev/null || echo "")
            echo "✓ Found primary: $container ($PRIMARY_HOST)"
            break
        fi
    fi
done

if [ -z "$MONGO_CONTAINER" ]; then
    echo "❌ Could not find primary MongoDB node"
    echo "   Make sure at least one MongoDB container is running and is primary"
    echo "   Check status: ./scripts/check-replica-set-status.sh"
    exit 1
fi

echo ""
echo "2. Checking current replica set status..."
echo "-------------------------------------------"
docker exec "$MONGO_CONTAINER" mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var status = rs.status();
      print('Current members:');
      status.members.forEach(function(m) {
        var priority = m.priority !== undefined ? m.priority : 1;
        print('  ' + m.name + ': ' + m.stateStr + ' (priority: ' + priority + ')');
      });
    } catch(e) {
      print('Error: ' + e.message);
      exit(1);
    }
  " 2>/dev/null

if [ $? -ne 0 ]; then
    echo "❌ Failed to get replica set status"
    exit 1
fi

echo ""
echo "3. Validating addition request..."
echo "-------------------------------------------"
VALIDATION_RESULT=$(docker exec "$MONGO_CONTAINER" mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var status = rs.status();
      
      // Check if peer already exists
      var existingMember = status.members.find(function(m) {
        return m.name === '$PEER_TO_ADD';
      });
      
      if (existingMember) {
        print('ALREADY_EXISTS');
        exit(0);
      }
      
      // Try to connect to the peer to verify it's reachable
      // Note: This is a basic check, actual connection will be tested during add
      print('OK');
    } catch(e) {
      print('ERROR: ' + e.message);
      exit(1);
    }
  " 2>/dev/null)

case "$VALIDATION_RESULT" in
    "ALREADY_EXISTS")
        echo "⚠️  Peer '$PEER_TO_ADD' already exists in replica set"
        echo "   No action needed"
        exit 0
        ;;
    "OK")
        echo "✓ Validation passed - peer can be added"
        ;;
    *)
        echo "❌ Validation error: $VALIDATION_RESULT"
        exit 1
        ;;
esac

echo ""
echo "4. Testing connectivity to new peer..."
echo "-------------------------------------------"
# Extract hostname and port from PEER_TO_ADD
PEER_HOST=$(echo "$PEER_TO_ADD" | cut -d: -f1)
PEER_PORT=$(echo "$PEER_TO_ADD" | cut -d: -f2)

# Try to ping the new peer (this might fail if it's a remote server, but we'll try)
# We'll use the primary container to test connectivity
CONNECTIVITY_TEST=$(docker exec "$MONGO_CONTAINER" mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --host "$PEER_TO_ADD" \
  --quiet \
  --eval "db.adminCommand('ping')" 2>/dev/null && echo "OK" || echo "FAILED")

if [ "$CONNECTIVITY_TEST" = "OK" ]; then
    echo "✓ Connectivity test passed"
else
    echo "⚠️  Could not test connectivity to $PEER_TO_ADD"
    echo "   This might be normal if:"
    echo "   - The peer is on a different server"
    echo "   - Network configuration is still being set up"
    echo "   - The peer is not yet started"
    echo ""
    echo "   Continuing anyway - MongoDB will verify connectivity during add..."
fi

echo ""
echo "5. Adding peer to replica set..."
echo "-------------------------------------------"
ADD_RESULT=$(docker exec "$MONGO_CONTAINER" mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      print('Adding member: $PEER_TO_ADD with priority: $PRIORITY');
      var result = rs.add({
        host: '$PEER_TO_ADD',
        priority: $PRIORITY
      });
      print('✅ Successfully added: ' + result.ok);
    } catch(e) {
      print('ERROR: ' + e.message);
      if (e.message.includes('already in the config')) {
        print('');
        print('Note: Member may already exist. Checking current config...');
        var cfg = rs.conf();
        var existing = cfg.members.find(function(m) { return m.host === '$PEER_TO_ADD'; });
        if (existing) {
          print('Member found in config with _id: ' + existing._id);
        }
      }
      exit(1);
    }
  " 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ Failed to add peer to replica set"
    echo "$ADD_RESULT"
    echo ""
    echo "Common issues:"
    echo "  - Peer must be running and accessible from primary"
    echo "  - Peer must have replica set configured (--replSet $REPLICA_SET_NAME)"
    echo "  - Peer must use the same keyfile and TLS certificates"
    echo "  - Network connectivity between nodes"
    exit 1
fi

echo "$ADD_RESULT"

echo ""
echo "6. Waiting for replica set to stabilize (15 seconds)..."
echo "-------------------------------------------"
sleep 15

echo ""
echo "7. Verifying final status..."
echo "-------------------------------------------"
docker exec "$MONGO_CONTAINER" mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var status = rs.status();
      print('Replica Set Status:');
      print('===================');
      print('Set Name: ' + status.set);
      print('');
      print('All members:');
      status.members.forEach(function(m) {
        var priority = m.priority !== undefined ? m.priority : 1;
        var health = m.health === 1 ? 'healthy' : 'unhealthy';
        var marker = '';
        if (m.name === '$PEER_TO_ADD') {
          marker = ' <-- NEW';
        }
        print('  ' + m.name + ': ' + m.stateStr + ' (priority: ' + priority + ', ' + health + ')' + marker);
      });
      print('');
      var primary = status.members.find(function(m) { return m.stateStr === 'PRIMARY'; });
      if (primary) {
        print('✅ Primary: ' + primary.name);
      } else {
        print('⚠️  No primary found (may be re-electing)');
      }
      print('');
      var newMember = status.members.find(function(m) { return m.name === '$PEER_TO_ADD'; });
      if (newMember) {
        if (newMember.stateStr === 'SECONDARY') {
          print('✅ New member is now SECONDARY and syncing data');
        } else if (newMember.stateStr === 'STARTUP2') {
          print('⏳ New member is STARTUP2 (initial sync in progress)');
        } else {
          print('ℹ️  New member state: ' + newMember.stateStr);
        }
      }
    } catch(e) {
      print('Error: ' + e.message);
    }
  " 2>/dev/null

echo ""
echo "=========================================="
echo "✅ Peer Added Successfully!"
echo "=========================================="
echo ""
echo "Peer '$PEER_TO_ADD' has been added to the replica set."
echo ""
echo "Note: If the peer is in STARTUP2 state, it's still syncing data."
echo "      This can take time depending on database size."
echo "      Check status: ./scripts/check-replica-set-status.sh"
echo ""
