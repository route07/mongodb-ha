#!/bin/bash
# Quick fix: Start MongoDB as standalone, create user, then restore replica set config

set -e

if [ ! -f .env ]; then
  echo "Error: .env file not found"
  exit 1
fi

export $(grep -v '^#' .env | xargs)

if [ -z "$MONGO_INITDB_ROOT_USERNAME" ] || [ -z "$MONGO_INITDB_ROOT_PASSWORD" ]; then
  echo "Error: MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD must be set in .env"
  exit 1
fi

echo "=========================================="
echo "Quick MongoDB User Fix"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Stop MongoDB"
echo "  2. Start as standalone (no replica set, no keyFile)"
echo "  3. Create the user"
echo "  4. Restore full configuration"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "Step 1: Stopping MongoDB..."
docker-compose stop mongodb-primary mongodb-secondary-1 mongodb-secondary-2 2>/dev/null || true
sleep 2

echo ""
echo "Step 2: Starting MongoDB as standalone (no replica set, no auth)..."
docker run -d --rm \
  --name mongo-primary-temp \
  --network ha-mongodb_db-network \
  -v $(pwd)/db_data_primary:/data/db \
  -v $(pwd)/tls-certs:/etc/mongo/ssl:ro \
  mongo:7.0 \
  mongod \
  --tlsMode requireTLS \
  --tlsCertificateKeyFile /etc/mongo/ssl/server.pem \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --tlsAllowConnectionsWithoutCertificates \
  --bind_ip_all

echo "Waiting for MongoDB to start (15 seconds)..."
sleep 15

# Wait for MongoDB to be ready
for i in {1..10}; do
  if docker exec mongo-primary-temp mongosh --tls \
    --tlsAllowInvalidCertificates \
    --tlsCAFile /etc/mongo/ssl/ca.crt \
    --eval "db.adminCommand('ping')" \
    --quiet \
    > /dev/null 2>&1; then
    echo "✓ MongoDB is ready"
    break
  fi
  if [ $i -eq 10 ]; then
    echo "✗ MongoDB failed to start"
    docker logs mongo-primary-temp
    docker stop mongo-primary-temp
    exit 1
  fi
  echo "   Waiting... ($i/10)"
  sleep 3
done

echo ""
echo "Step 3: Creating root user..."
CREATE_RESULT=$(docker exec mongo-primary-temp mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --quiet \
  --eval "
    try {
      db.getSiblingDB('admin').createUser({
        user: '$MONGO_INITDB_ROOT_USERNAME',
        pwd: '$MONGO_INITDB_ROOT_PASSWORD',
        roles: [{ role: 'root', db: 'admin' }]
      });
      print('SUCCESS');
    } catch (e) {
      if (e.code === 51003 || e.message.includes('already exists')) {
        print('ALREADY_EXISTS');
      } else {
        print('ERROR: ' + e.message);
        throw e;
      }
    }
  " 2>&1)

if echo "$CREATE_RESULT" | grep -q "SUCCESS\|ALREADY_EXISTS"; then
  echo "✓ User created successfully"
else
  echo "✗ Failed to create user: $CREATE_RESULT"
  docker stop mongo-primary-temp
  exit 1
fi

echo ""
echo "Step 4: Verifying user..."
if docker exec mongo-primary-temp mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  echo "✓ User verified - authentication works!"
else
  echo "✗ User created but authentication fails"
  docker stop mongo-primary-temp
  exit 1
fi

echo ""
echo "Step 5: Stopping temporary container..."
docker stop mongo-primary-temp
sleep 2

echo ""
echo "Step 6: Starting MongoDB with full configuration..."
docker-compose up -d mongodb-primary

echo "Waiting for MongoDB to start (20 seconds)..."
sleep 20

echo ""
echo "Step 7: Verifying with full configuration..."
if docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  echo "✓✓✓ SUCCESS! User works with full configuration!"
  echo ""
  echo "Your MongoDB setup is now working correctly."
  echo "You can now start the secondary nodes and initialize the replica set."
else
  echo "✗ Authentication fails with full configuration"
  echo "   Check logs: docker-compose logs mongodb-primary"
  exit 1
fi
