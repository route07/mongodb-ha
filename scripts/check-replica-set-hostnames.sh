#!/bin/bash
# Script to check what hostnames the replica set is using

echo "=========================================="
echo "Checking Replica Set Member Hostnames"
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

echo "Connecting to MongoDB to check replica set configuration..."
echo ""

# Get replica set status
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
      print('Replica Set Name: ' + status.set);
      print('');
      print('Member Hostnames:');
      status.members.forEach(function(member) {
        print('  - ' + member.name + ' (state: ' + member.stateStr + ')');
      });
      print('');
      print('To fix connection issues from remote servers:');
      print('  Add these hostnames to /etc/hosts on your app server:');
      status.members.forEach(function(member) {
        var hostname = member.name.split(':')[0];
        print('    <MONGODB_SERVER_IP> ' + hostname);
      });
    } catch(e) {
      print('Error: ' + e.message);
      print('Replica set may not be initialized yet.');
    }
  " 2>/dev/null

if [ $? -ne 0 ]; then
    echo ""
    echo "⚠️  Failed to connect to MongoDB or get replica set status"
    echo "   Make sure:"
    echo "   1. MongoDB containers are running: docker-compose ps"
    echo "   2. Replica set is initialized"
    echo "   3. Credentials in .env are correct"
fi

echo ""
echo "=========================================="
