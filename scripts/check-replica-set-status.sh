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

echo "2. Checking replica set status..."
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
      print('Set Name: ' + status.set);
      print('');
      print('Members:');
      var hasPrimary = false;
      status.members.forEach(function(m) {
        var health = m.health === 1 ? '✓ healthy' : '✗ unhealthy';
        var state = m.stateStr;
        if (state === 'PRIMARY') {
          hasPrimary = true;
          state = 'PRIMARY ⭐';
        }
        print('  ' + m.name + ': ' + state + ' (' + health + ')');
      });
      print('');
      if (hasPrimary) {
        print('✅ Primary node is active');
      } else {
        print('⚠️  No primary node found');
        print('   This is normal after restart - waiting 30-60 seconds...');
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
    echo "⚠️  Failed to connect to MongoDB"
    echo "   Make sure containers are running: docker-compose ps"
fi

echo ""
echo "3. Checking isMaster..."
echo "-------------------------------------------"
docker exec mongo-primary mongosh --tls \
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
  " 2>/dev/null

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
