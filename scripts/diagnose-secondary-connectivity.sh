#!/bin/bash
# Script to diagnose why a secondary node is unreachable

set -e

echo "=========================================="
echo "Diagnosing Secondary Node Connectivity"
echo "=========================================="
echo ""

if [ -z "$1" ]; then
    echo "Usage: $0 <secondary-ip>"
    echo "Example: $0 192.168.2.6"
    exit 1
fi

SECONDARY_IP="$1"
echo "Checking connectivity to: $SECONDARY_IP:27017"
echo ""

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found. Make sure you're in the ha-mongodb directory."
    exit 1
fi

source .env

echo "1. Basic Network Connectivity"
echo "-------------------------------------------"
if ping -c 2 "$SECONDARY_IP" > /dev/null 2>&1; then
    echo "✅ Server is reachable via ping"
else
    echo "❌ Server is NOT reachable via ping"
    echo "   Check:"
    echo "   - Server is running"
    echo "   - IP address is correct"
    echo "   - Network routing"
    exit 1
fi

echo ""
echo "2. Port 27017 Accessibility"
echo "-------------------------------------------"
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$SECONDARY_IP/27017" 2>/dev/null; then
    echo "✅ Port 27017 is open and accessible"
else
    echo "❌ Port 27017 is NOT accessible"
    echo "   Possible causes:"
    echo "   - MongoDB not running on new server"
    echo "   - Firewall blocking port 27017"
    echo "   - MongoDB not bound to 0.0.0.0 (only listening on localhost)"
    echo ""
    echo "   Check on new server:"
    echo "   - docker ps (is container running?)"
    echo "   - docker logs mongo-secondary-2"
    echo "   - sudo ufw status (firewall rules)"
    echo "   - netstat -tlnp | grep 27017 (is MongoDB listening?)"
fi

echo ""
echo "3. MongoDB Connection Test"
echo "-------------------------------------------"
echo "Attempting to connect to MongoDB..."
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --host "$SECONDARY_IP:27017" \
  --quiet \
  --eval "db.adminCommand('ping')" 2>&1 | head -5

if [ $? -eq 0 ]; then
    echo "✅ Can connect to MongoDB"
else
    echo "❌ Cannot connect to MongoDB"
    echo "   Check TLS certificates and authentication"
fi

echo ""
echo "4. Replica Set Member Status"
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
      var member = status.members.find(m => m.name.includes('$SECONDARY_IP'));
      if (member) {
        print('Member found:');
        print('  Name: ' + member.name);
        print('  State: ' + member.stateStr);
        print('  Health: ' + (member.health === 1 ? 'healthy' : 'unhealthy'));
        if (member.lastHeartbeatMessage) {
          print('  Last message: ' + member.lastHeartbeatMessage);
        }
        if (member.stateStr === 'STARTUP2' || member.stateStr === 'RECOVERING') {
          print('  ℹ️  Node is syncing data (this is normal for new nodes)');
        }
      } else {
        print('⚠️  Member not found in replica set status');
      }
    } catch(e) {
      print('Error: ' + e.message);
    }
  " 2>/dev/null

echo ""
echo "5. Checklist for New Server"
echo "-------------------------------------------"
echo "On the new server ($SECONDARY_IP), verify:"
echo ""
echo "  [ ] MongoDB container is running:"
echo "      docker ps | grep mongo-secondary-2"
echo ""
echo "  [ ] Container is healthy:"
echo "      docker-compose ps"
echo ""
echo "  [ ] MongoDB is listening on all interfaces:"
echo "      docker exec mongo-secondary-2 netstat -tlnp | grep 27017"
echo "      Should show: 0.0.0.0:27017 (not 127.0.0.1:27017)"
echo ""
echo "  [ ] Firewall allows port 27017:"
echo "      sudo ufw status | grep 27017"
echo "      Or: sudo ufw allow from <primary-ip> to any port 27017"
echo ""
echo "  [ ] keyFile exists and matches:"
echo "      ls -la tls-certs/keyfile"
echo "      md5sum tls-certs/keyfile  # Compare with other nodes"
echo ""
echo "  [ ] TLS certificates exist:"
echo "      ls -la tls-certs/"
echo ""
echo "  [ ] Container logs show no errors:"
echo "      docker logs mongo-secondary-2 | tail -50"
echo ""

echo "=========================================="
echo "Diagnosis Complete"
echo "=========================================="
