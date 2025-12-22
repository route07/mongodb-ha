#!/bin/bash
# Script to check replica set status and help fix issues

echo "=========================================="
echo "MongoDB Replica Set Status Check"
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

echo "1. Checking container status..."
echo "-------------------------------------------"
docker-compose ps | grep mongodb
echo ""

echo "2. Finding available MongoDB node..."
echo "-------------------------------------------"
# Try to find a running MongoDB container
MONGO_CONTAINER=""
for container in mongo-primary mongodb-secondary-1 mongodb-secondary-2; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        MONGO_CONTAINER="$container"
        echo "✓ Found running container: $container"
        break
    fi
done

if [ -z "$MONGO_CONTAINER" ]; then
    echo "❌ No MongoDB containers are running"
    echo "   Start containers: docker-compose up -d"
    exit 1
fi

echo ""
echo "3. Checking replica set status..."
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
      print('Set Name: ' + status.set);
      print('');
      print('Members:');
      var hasPrimary = false;
      var primaryName = '';
      status.members.forEach(function(m) {
        var health = m.health === 1 ? '✓ healthy' : '✗ unhealthy';
        var state = m.stateStr;
        if (state === 'PRIMARY') {
          hasPrimary = true;
          primaryName = m.name;
          state = 'PRIMARY ⭐';
        }
        var containerStatus = '';
        try {
          // Check if container is running (this won't work from inside, but we'll show the state)
        } catch(e) {}
        print('  ' + m.name + ': ' + state + ' (' + health + ')');
      });
      print('');
      if (hasPrimary) {
        print('✅ Primary node is active: ' + primaryName);
      } else {
        print('⚠️  No primary node found');
        print('   This can happen if:');
        print('   - Primary container is stopped');
        print('   - Replica set is re-electing (wait 30-60 seconds)');
        print('   - Network issues between nodes');
        print('');
        print('   If it persists, run: ./scripts/fix-replica-set.sh');
      }
    } catch(e) {
      print('❌ Error: ' + e.message);
      if (e.message.includes('no replset config')) {
        print('');
        print('⚠️  Replica set is not initialized');
        print('   Run: ./scripts/init-replica-set.sh');
      }
    }
  " 2>/dev/null

if [ $? -ne 0 ]; then
    echo "⚠️  Failed to connect to MongoDB via $MONGO_CONTAINER"
    echo "   Check container logs: docker logs $MONGO_CONTAINER"
fi

echo ""
echo "4. Checking isMaster on $MONGO_CONTAINER..."
echo "-------------------------------------------"
docker exec "$MONGO_CONTAINER" mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    var result = rs.isMaster();
    print('Is Primary: ' + (result.ismaster ? 'YES ✅' : 'NO ❌'));
    print('Set Name: ' + (result.setName || 'N/A'));
    print('Primary: ' + (result.primary || 'N/A'));
    if (!result.ismaster && result.primary) {
      print('');
      print('ℹ️  This node is not primary. Primary is: ' + result.primary);
    }
  " 2>/dev/null

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
