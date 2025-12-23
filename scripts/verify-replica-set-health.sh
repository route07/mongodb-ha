#!/bin/bash
# Script to verify replica set health after fixing connectivity

echo "=========================================="
echo "Verifying Replica Set Health"
echo "=========================================="
echo ""

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found. Make sure you're in the ha-mongodb directory."
    exit 1
fi

source .env

echo "Checking replica set status..."
echo "-------------------------------------------"
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    var status = rs.status();
    print('=== Replica Set Status ===');
    print('');
    var allHealthy = true;
    var hasPrimary = false;
    
    status.members.forEach(function(m) {
      var health = m.health === 1 ? '✓ healthy' : '✗ unhealthy';
      var state = m.stateStr;
      
      if (m.stateStr === 'PRIMARY') {
        hasPrimary = true;
        state = 'PRIMARY ⭐';
      }
      
      print(health + ' | ' + m.name + ': ' + state);
      
      if (m.health !== 1) {
        allHealthy = false;
        if (m.lastHeartbeatMessage) {
          print('    Error: ' + m.lastHeartbeatMessage);
        }
      }
      
      if (m.stateStr === 'STARTUP' || m.stateStr === 'STARTUP2') {
        print('    → Initial sync in progress (this is normal)');
      }
      
      if (m.stateStr === 'SECONDARY' && m.optimeDate) {
        var lag = new Date() - m.optimeDate;
        var lagSeconds = Math.round(lag/1000);
        print('    → Replication lag: ' + lagSeconds + ' seconds');
        if (lagSeconds > 60) {
          print('    ⚠️  High replication lag');
        }
      }
    });
    
    print('');
    if (allHealthy && hasPrimary) {
      print('✅ Replica set is healthy!');
    } else if (!allHealthy) {
      print('⚠️  Some nodes are unhealthy - check errors above');
    } else if (!hasPrimary) {
      print('⚠️  No primary node - waiting for election...');
    }
  " 2>/dev/null

if [ $? -ne 0 ]; then
    echo "⚠️  Failed to connect to MongoDB"
    echo "   Make sure containers are running: docker-compose ps"
fi

echo ""
echo "=========================================="
echo "Connection Test"
echo "=========================================="
echo ""

# Test connection to secondary-2
SECONDARY_IP="192.168.2.6"
echo "Testing connection to secondary-2 ($SECONDARY_IP:27017)..."
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$SECONDARY_IP/27017" 2>/dev/null; then
    echo "✅ Port 27017 is accessible"
else
    echo "❌ Port 27017 is NOT accessible"
fi

echo ""
echo "=========================================="
