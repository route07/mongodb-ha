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

# Function to get exposed port for a container
get_exposed_port() {
  local container=$1
  local internal_port=${2:-27017}
  # Try docker port first
  local exposed=$(docker port "$container" "$internal_port/tcp" 2>/dev/null | cut -d: -f2)
  if [ -n "$exposed" ]; then
    echo "$exposed"
    return
  fi
  # Fallback: try to get from docker-compose ps output
  local compose_output=$(docker-compose ps --format json 2>/dev/null | grep -A 5 "\"$container\"" | grep -oP '"ports":\s*"[\d.]+:(\d+)"' | head -1 | grep -oP ':\K\d+' || echo "")
  if [ -n "$compose_output" ]; then
    echo "$compose_output"
    return
  fi
  # Default fallback based on container name
  case "$container" in
    mongo-primary)
      echo "${MONGO_PORT:-27017}"
      ;;
    mongo-secondary-1|mongodb-secondary-1)
      echo "${MONGO_SECONDARY1_PORT:-27018}"
      ;;
    mongo-secondary-2|mongodb-secondary-2)
      echo "${MONGO_SECONDARY2_PORT:-27019}"
      ;;
    *)
      echo "$internal_port"
      ;;
  esac
}

# Map container names to their exposed ports
PRIMARY_EXPOSED_PORT=$(get_exposed_port "mongo-primary" 27017)
SECONDARY1_EXPOSED_PORT=$(get_exposed_port "mongo-secondary-1" 27017)
SECONDARY2_EXPOSED_PORT=$(get_exposed_port "mongo-secondary-2" 27017)

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
      print('Members (Internal Replica Set Config):');
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

echo ""
echo "4. External Port Mapping (for client connections):"
echo "-------------------------------------------"
echo "  Primary (mongo-primary):     localhost:${PRIMARY_EXPOSED_PORT}"
echo "  Secondary-1 (mongo-secondary-1): localhost:${SECONDARY1_EXPOSED_PORT}"
echo "  Secondary-2 (mongo-secondary-2): localhost:${SECONDARY2_EXPOSED_PORT}"
echo ""
echo "  Connection String (recommended):"
echo "  mongodb://user:pass@localhost:${PRIMARY_EXPOSED_PORT},localhost:${SECONDARY1_EXPOSED_PORT},localhost:${SECONDARY2_EXPOSED_PORT}/db?replicaSet=rs0&tls=..."
echo ""

if [ $? -ne 0 ]; then
    echo "⚠️  Failed to connect to MongoDB via $MONGO_CONTAINER"
    echo "   Check container logs: docker logs $MONGO_CONTAINER"
fi

echo ""
echo "5. Checking isMaster on $MONGO_CONTAINER..."
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
