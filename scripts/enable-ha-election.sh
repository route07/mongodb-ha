#!/bin/bash
# Script to re-enable HA election - restores normal failover behavior

set -e

echo "=========================================="
echo "Re-enabling HA Election"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Set primary priority to 2 (normal)"
echo "  2. Set secondary priorities to 1 (normal)"
echo "  3. Unfreeze secondaries"
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
PRIMARY_HOST="mongodb-primary"
SECONDARY1_HOST="mongodb-secondary-1"
SECONDARY2_HOST="mongodb-secondary-2"
PORT=27017

# Find primary container
echo "1. Finding primary MongoDB node..."
echo "-------------------------------------------"
MONGO_CONTAINER=""
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
            echo "✓ Found primary: $container"
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
echo "2. Unfreezing secondary nodes..."
echo "-------------------------------------------"

# Unfreeze secondary 1 if it exists and is running
if docker ps --format '{{.Names}}' | grep -q "^mongodb-secondary-1$"; then
    echo "Unfreezing mongodb-secondary-1..."
    docker exec mongodb-secondary-1 mongosh --tls \
      --tlsAllowInvalidCertificates \
      --tlsCAFile /etc/mongo/ssl/ca.crt \
      -u "$MONGO_INITDB_ROOT_USERNAME" \
      -p "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --quiet \
      --eval "rs.freeze(0)" 2>/dev/null && echo "✓ Unfrozen" || echo "⚠️  Could not unfreeze (may not be frozen)"
fi

# Unfreeze secondary 2 if it exists and is running
if docker ps --format '{{.Names}}' | grep -q "^mongodb-secondary-2$"; then
    echo "Unfreezing mongodb-secondary-2..."
    docker exec mongodb-secondary-2 mongosh --tls \
      --tlsAllowInvalidCertificates \
      --tlsCAFile /etc/mongo/ssl/ca.crt \
      -u "$MONGO_INITDB_ROOT_USERNAME" \
      -p "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --quiet \
      --eval "rs.freeze(0)" 2>/dev/null && echo "✓ Unfrozen" || echo "⚠️  Could not unfreeze (may not be frozen)"
fi

echo ""
echo "3. Restoring normal replica set priorities..."
echo "-------------------------------------------"
docker exec "$MONGO_CONTAINER" mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    var cfg = rs.conf();
    
    // Restore normal priorities
    cfg.members.forEach(function(m) {
      if (m.host.includes('primary')) {
        m.priority = 2;  // Normal priority for primary
        print('✓ Set ' + m.host + ' priority to 2 (primary)');
      } else {
        m.priority = 1;  // Normal priority for secondaries
        print('✓ Set ' + m.host + ' priority to 1 (secondary)');
      }
    });
    
    // Apply configuration
    rs.reconfig(cfg, {force: false});
    print('');
    print('✅ Replica set configuration restored to normal');
  " 2>/dev/null

if [ $? -ne 0 ]; then
    echo "❌ Failed to update replica set configuration"
    exit 1
fi

echo ""
echo "4. Verifying configuration..."
echo "-------------------------------------------"
docker exec "$MONGO_CONTAINER" mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    var status = rs.status();
    print('Replica Set Status:');
    print('===================');
    status.members.forEach(function(m) {
      var priority = m.priority !== undefined ? m.priority : 1;
      print('  ' + m.name + ': ' + m.stateStr + ' (priority: ' + priority + ')');
    });
    print('');
    var primary = status.members.find(function(m) { return m.stateStr === 'PRIMARY'; });
    if (primary) {
      print('✅ Primary: ' + primary.name + ' (priority: ' + primary.priority + ')');
      print('✅ Elections are ENABLED - automatic failover is active');
    } else {
      print('⚠️  No primary found');
    }
  " 2>/dev/null

echo ""
echo "=========================================="
echo "✅ HA Election Re-enabled Successfully!"
echo "=========================================="
echo ""
echo "Normal failover behavior is now restored."
echo "If primary fails, a secondary will automatically become primary."
echo ""
