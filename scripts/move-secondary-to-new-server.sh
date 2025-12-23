#!/bin/bash
# Script to help move a secondary node to a new server

set -e

echo "=========================================="
echo "Move Secondary Node to New Server"
echo "=========================================="
echo ""
echo "This script helps you move mongodb-secondary-2 to a new server."
echo ""

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found. Make sure you're in the ha-mongodb directory."
    exit 1
fi

source .env

# Check if required variables are set
if [ -z "$MONGO_INITDB_ROOT_USERNAME" ] || [ -z "$MONGO_INITDB_ROOT_PASSWORD" ]; then
    echo "⚠️  MONGO_INITDB_ROOT_USERNAME or MONGO_INITDB_ROOT_PASSWORD not set in .env"
    exit 1
fi

echo "Step 1: Check current replica set status..."
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
    print('Current members:');
    status.members.forEach(function(m) {
      print('  ' + m.name + ': ' + m.stateStr);
    });
  " 2>/dev/null

echo ""
read -p "Do you want to proceed with removing mongodb-secondary-2? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Step 2: Removing mongodb-secondary-2 from replica set..."
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
      rs.remove('mongodb-secondary-2:27017');
      print('✅ Removed mongodb-secondary-2 from replica set');
    } catch(e) {
      print('Error: ' + e.message);
      if (e.message.includes('not found')) {
        print('   Secondary-2 may already be removed or not in replica set');
      }
    }
  " 2>/dev/null

echo ""
echo "Step 3: Stopping mongodb-secondary-2 container..."
echo "-------------------------------------------"
docker-compose stop mongodb-secondary-2 2>/dev/null && echo "✅ Stopped" || echo "⚠️  Container may already be stopped"

echo ""
echo "Step 4: Files to copy to new server"
echo "-------------------------------------------"
echo "You need to copy these files to the new server:"
echo ""
echo "1. TLS certificates and keyFile (CRITICAL - must be identical):"
echo "   - tls-certs/ca.crt"
echo "   - tls-certs/server.pem"
echo "   - tls-certs/client.pem"
echo "   - tls-certs/keyfile  ⚠️  MUST BE IDENTICAL"
echo ""
echo "2. Configuration files:"
echo "   - .env"
echo "   - docker-compose.yaml (or create docker-compose-secondary2.yaml)"
echo ""
echo "3. Scripts (optional but recommended):"
echo "   - scripts/"
echo ""
echo "Quick copy command (from this server):"
echo "  scp -r tls-certs/ user@new-server:~/ha-mongodb/tls-certs/"
echo "  scp .env user@new-server:~/ha-mongodb/.env"
echo ""

read -p "Press Enter when you've copied files to new server and are ready to add it back..."

echo ""
echo "Step 5: Add secondary-2 back to replica set"
echo "-------------------------------------------"
read -p "Enter new server IP or hostname: " NEW_HOST

if [ -z "$NEW_HOST" ]; then
    echo "⚠️  Hostname/IP required"
    exit 1
fi

echo ""
echo "Adding mongodb-secondary-2 at $NEW_HOST:27017..."
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      rs.add({
        _id: 2,
        host: '$NEW_HOST:27017',
        priority: 1
      });
      print('✅ Added mongodb-secondary-2 at $NEW_HOST:27017');
      print('');
      print('Waiting 10 seconds for initial connection...');
    } catch(e) {
      print('Error: ' + e.message);
      if (e.message.includes('duplicate')) {
        print('   Node may already be in replica set');
      }
    }
  " 2>/dev/null

sleep 10

echo ""
echo "Step 6: Verify replica set status..."
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
    print('Replica Set Members:');
    status.members.forEach(function(m) {
      var health = m.health === 1 ? 'healthy' : 'unhealthy';
      print('  ' + m.name + ': ' + m.stateStr + ' (' + health + ')');
      if (m.stateStr === 'SECONDARY' && m.optimeDate) {
        var lag = new Date() - m.optimeDate;
        print('    Replication lag: ' + Math.round(lag/1000) + ' seconds');
      }
    });
  " 2>/dev/null

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
echo ""
echo "Next steps on new server:"
echo "1. Ensure MongoDB is running: docker-compose up -d mongodb-secondary-2"
echo "2. Check logs: docker logs mongo-secondary-2"
echo "3. Monitor replication lag until it's minimal (< 10 seconds)"
echo ""
echo "See docs/MOVE_SECONDARY_TO_NEW_SERVER.md for detailed instructions"
