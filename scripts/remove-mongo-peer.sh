#!/bin/bash
# Script to remove a MongoDB peer from the replica set
# Usage: ./scripts/remove-mongo-peer.sh <hostname_or_container>
# Example: ./scripts/remove-mongo-peer.sh mongodb-secondary-1:27017
#          ./scripts/remove-mongo-peer.sh mongodb-secondary-1

set -e

echo "=========================================="
echo "Remove MongoDB Peer from Replica Set"
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

# Check if peer hostname/container is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <hostname_or_container>"
    echo ""
    echo "Examples:"
    echo "  $0 mongodb-secondary-1:27017"
    echo "  $0 mongodb-secondary-1"
    echo "  $0 mongodb-secondary-2:27017"
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
                print('  ' + m.name + ': ' + m.stateStr);
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

PEER_TO_REMOVE="$1"
REPLICA_SET_NAME=${REPLICA_SET_NAME:-rs0}
PORT=27017

# Normalize peer hostname (add port if not present)
if [[ ! "$PEER_TO_REMOVE" == *":"* ]]; then
    PEER_TO_REMOVE="${PEER_TO_REMOVE}:${PORT}"
fi

echo "Target peer to remove: $PEER_TO_REMOVE"
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
        var marker = '';
        if (m.name === '$PEER_TO_REMOVE') {
          marker = ' <-- TARGET';
        }
        if (m.stateStr === 'PRIMARY') {
          marker += ' (PRIMARY)';
        }
        print('  ' + m.name + ': ' + m.stateStr + marker);
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
echo "3. Validating removal request..."
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
      var memberToRemove = status.members.find(function(m) {
        return m.name === '$PEER_TO_REMOVE';
      });
      
      if (!memberToRemove) {
        print('NOT_FOUND');
        exit(0);
      }
      
      if (memberToRemove.stateStr === 'PRIMARY') {
        print('IS_PRIMARY');
        exit(0);
      }
      
      var totalMembers = status.members.length;
      if (totalMembers <= 1) {
        print('LAST_MEMBER');
        exit(0);
      }
      
      print('OK');
    } catch(e) {
      print('ERROR: ' + e.message);
      exit(1);
    }
  " 2>/dev/null)

case "$VALIDATION_RESULT" in
    "NOT_FOUND")
        echo "❌ Peer '$PEER_TO_REMOVE' not found in replica set"
        echo "   Check the hostname and try again"
        exit 1
        ;;
    "IS_PRIMARY")
        echo "❌ Cannot remove primary node: $PEER_TO_REMOVE"
        echo ""
        echo "   To remove the primary, you must:"
        echo "   1. Step down the primary first:"
        echo "      docker exec $MONGO_CONTAINER mongosh --tls --tlsAllowInvalidCertificates --tlsCAFile /etc/mongo/ssl/ca.crt -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval 'rs.stepDown(60)'"
        echo "   2. Wait for a new primary to be elected"
        echo "   3. Then run this script again"
        exit 1
        ;;
    "LAST_MEMBER")
        echo "❌ Cannot remove the last member of the replica set"
        echo "   A replica set must have at least one member"
        exit 1
        ;;
    "OK")
        echo "✓ Validation passed - peer can be removed"
        ;;
    *)
        echo "❌ Validation error: $VALIDATION_RESULT"
        exit 1
        ;;
esac

echo ""
echo "4. Removing peer from replica set..."
echo "-------------------------------------------"
REMOVE_RESULT=$(docker exec "$MONGO_CONTAINER" mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var status = rs.status();
      var memberToRemove = status.members.find(function(m) {
        return m.name === '$PEER_TO_REMOVE';
      });
      
      if (!memberToRemove) {
        print('ERROR: Member not found');
        exit(1);
      }
      
      print('Removing member with _id: ' + memberToRemove._id);
      var result = rs.remove('$PEER_TO_REMOVE');
      print('✅ Successfully removed: ' + result.ok);
    } catch(e) {
      print('ERROR: ' + e.message);
      exit(1);
    }
  " 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ Failed to remove peer from replica set"
    echo "$REMOVE_RESULT"
    exit 1
fi

echo "$REMOVE_RESULT"

echo ""
echo "5. Waiting for replica set to stabilize (10 seconds)..."
echo "-------------------------------------------"
sleep 10

echo ""
echo "6. Verifying final status..."
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
      print('Remaining members:');
      status.members.forEach(function(m) {
        var health = m.health === 1 ? 'healthy' : 'unhealthy';
        print('  ' + m.name + ': ' + m.stateStr + ' (' + health + ')');
      });
      print('');
      var primary = status.members.find(function(m) { return m.stateStr === 'PRIMARY'; });
      if (primary) {
        print('✅ Primary: ' + primary.name);
      } else {
        print('⚠️  No primary found (may be re-electing)');
      }
    } catch(e) {
      print('Error: ' + e.message);
    }
  " 2>/dev/null

echo ""
echo "=========================================="
echo "✅ Peer Removed Successfully!"
echo "=========================================="
echo ""
echo "Peer '$PEER_TO_REMOVE' has been removed from the replica set."
echo ""
echo "Note: The container may still be running. To stop it:"
echo "  docker stop <container-name>"
echo "  docker-compose stop <service-name>"
echo ""
