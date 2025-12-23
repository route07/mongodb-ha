#!/bin/bash
# Script to disable HA election - keeps current primary as primary always
# This prevents automatic failover until you re-enable it

set -e

echo "=========================================="
echo "Disabling HA Election"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Set primary priority to 100 (very high)"
echo "  2. Set secondary priorities to 0 (prevents election)"
echo "  3. Freeze secondaries to prevent elections"
echo ""
echo "⚠️  WARNING: This disables automatic failover!"
echo "   If primary fails, no secondary will become primary automatically."
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
echo "2. Getting current replica set configuration..."
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
    print('Current configuration:');
    cfg.members.forEach(function(m) {
      print('  ' + m.host + ': priority=' + (m.priority || 1));
    });
  " 2>/dev/null

echo ""
echo "3. Updating replica set configuration to disable elections..."
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
    
    // Update priorities
    cfg.members.forEach(function(m) {
      if (m.stateStr === 'PRIMARY' || m.host.includes('primary')) {
        m.priority = 100;  // Very high priority for primary
        print('✓ Set ' + m.host + ' priority to 100 (primary)');
      } else {
        m.priority = 0;  // Zero priority prevents election
        print('✓ Set ' + m.host + ' priority to 0 (cannot be elected)');
      }
    });
    
    // Apply configuration
    rs.reconfig(cfg, {force: false});
    print('');
    print('✅ Replica set configuration updated');
  " 2>/dev/null

if [ $? -ne 0 ]; then
    echo "❌ Failed to update replica set configuration"
    exit 1
fi

echo ""
echo "4. Freezing secondary nodes to prevent elections..."
echo "-------------------------------------------"

# Freeze secondary 1 if it exists and is running
if docker ps --format '{{.Names}}' | grep -q "^mongodb-secondary-1$"; then
    echo "Freezing mongodb-secondary-1..."
    docker exec mongodb-secondary-1 mongosh --tls \
      --tlsAllowInvalidCertificates \
      --tlsCAFile /etc/mongo/ssl/ca.crt \
      -u "$MONGO_INITDB_ROOT_USERNAME" \
      -p "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --quiet \
      --eval "rs.freeze(86400)" 2>/dev/null && echo "✓ Frozen for 24 hours" || echo "⚠️  Could not freeze (may already be frozen or not a secondary)"
fi

# Freeze secondary 2 if it exists and is running
if docker ps --format '{{.Names}}' | grep -q "^mongodb-secondary-2$"; then
    echo "Freezing mongodb-secondary-2..."
    docker exec mongodb-secondary-2 mongosh --tls \
      --tlsAllowInvalidCertificates \
      --tlsCAFile /etc/mongo/ssl/ca.crt \
      -u "$MONGO_INITDB_ROOT_USERNAME" \
      -p "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --quiet \
      --eval "rs.freeze(86400)" 2>/dev/null && echo "✓ Frozen for 24 hours" || echo "⚠️  Could not freeze (may already be frozen or not a secondary)"
fi

echo ""
echo "5. Verifying configuration..."
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
      var frozen = m.stateStr === 'SECONDARY' ? ' (frozen)' : '';
      print('  ' + m.name + ': ' + m.stateStr + ' (priority: ' + priority + ')' + frozen);
    });
    print('');
    var primary = status.members.find(function(m) { return m.stateStr === 'PRIMARY'; });
    if (primary) {
      print('✅ Primary: ' + primary.name + ' (priority: ' + primary.priority + ')');
      print('✅ Elections are DISABLED - primary will remain primary');
    } else {
      print('⚠️  No primary found');
    }
  " 2>/dev/null

echo ""
echo "=========================================="
echo "✅ HA Election Disabled Successfully!"
echo "=========================================="
echo ""
echo "Current primary will remain primary until you:"
echo "  1. Re-enable elections: ./scripts/enable-ha-election.sh"
echo "  2. Manually change priorities"
echo "  3. Unfreeze secondaries"
echo ""
echo "⚠️  IMPORTANT: If primary fails, no automatic failover will occur!"
echo "   You will need to manually promote a secondary if needed."
echo ""
