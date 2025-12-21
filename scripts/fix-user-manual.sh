#!/bin/bash
# Manual fix for MongoDB user when keyFile requires auth but user doesn't exist
# This script will guide you through the fix step by step

set -e

echo "=========================================="
echo "Manual MongoDB User Fix"
echo "=========================================="
echo ""
echo "This script will:"
echo "  1. Stop MongoDB containers"
echo "  2. Temporarily modify docker-compose to remove keyFile"
echo "  3. Start MongoDB without authentication"
echo "  4. Create the root user"
echo "  5. Restore original configuration"
echo "  6. Restart with authentication enabled"
echo ""

# Check .env
if [ ! -f .env ]; then
  echo "✗ .env file not found"
  exit 1
fi

export $(grep -v '^#' .env | xargs)

if [ -z "$MONGO_INITDB_ROOT_USERNAME" ] || [ -z "$MONGO_INITDB_ROOT_PASSWORD" ]; then
  echo "✗ MONGO_INITDB_ROOT_USERNAME or MONGO_INITDB_ROOT_PASSWORD not set in .env"
  exit 1
fi

echo "Username: $MONGO_INITDB_ROOT_USERNAME"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "Step 1: Stopping MongoDB containers..."
docker-compose stop mongodb-primary mongodb-secondary-1 mongodb-secondary-2 2>/dev/null || true
sleep 2

echo ""
echo "Step 2: Backing up docker-compose.yaml..."
cp docker-compose.yaml docker-compose.yaml.backup

echo ""
echo "Step 3: Creating temporary docker-compose without keyFile..."
# Use sed to remove --keyFile lines from mongodb-primary command
sed -e '/mongodb-primary:/,/^  [a-z]/ {
  /--keyFile/d
  /keyFile/d
}' docker-compose.yaml > docker-compose.tmp.yaml

# Also remove from secondary commands to be safe
sed -i -e '/mongodb-secondary-1:/,/^  [a-z]/ {
  /--keyFile/d
  /keyFile/d
}' docker-compose.tmp.yaml

sed -i -e '/mongodb-secondary-2:/,/^  [a-z]/ {
  /--keyFile/d
  /keyFile/d
}' docker-compose.tmp.yaml

if [ ! -f docker-compose.tmp.yaml ]; then
  echo "✗ Failed to create temporary docker-compose file"
  exit 1
fi

echo "✓ Created docker-compose.tmp.yaml (without keyFile)"

echo ""
echo "Step 4: Starting MongoDB primary WITHOUT keyFile (no auth)..."
docker-compose -f docker-compose.tmp.yaml up -d mongodb-primary

echo "Waiting for MongoDB to start (30 seconds)..."
sleep 30

# Check if MongoDB is ready
for i in {1..10}; do
  if docker exec mongo-primary mongosh --tls \
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
    echo "   Check logs: docker-compose -f docker-compose.tmp.yaml logs mongodb-primary"
    exit 1
  fi
  echo "   Waiting... ($i/10)"
  sleep 3
done

echo ""
echo "Step 5: Creating root user..."
CREATE_RESULT=$(docker exec mongo-primary mongosh --tls \
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
  echo ""
  echo "Restoring original configuration..."
  mv docker-compose.yaml.backup docker-compose.yaml
  rm -f docker-compose.tmp.yaml
  exit 1
fi

echo ""
echo "Step 6: Stopping MongoDB..."
docker-compose -f docker-compose.tmp.yaml stop mongodb-primary
sleep 2

echo ""
echo "Step 7: Restoring original docker-compose.yaml..."
mv docker-compose.yaml.backup docker-compose.yaml
rm -f docker-compose.tmp.yaml

echo ""
echo "Step 8: Starting MongoDB with full configuration (with auth)..."
docker-compose up -d

echo "Waiting for MongoDB to start (20 seconds)..."
sleep 20

echo ""
echo "Step 9: Verifying user works with authentication..."
if docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  echo "✓✓✓ SUCCESS! User created and authentication works!"
  echo ""
  echo "Your MongoDB setup is now working correctly."
  echo "You can now start the secondary nodes and initialize the replica set."
else
  echo "✗ Authentication still fails"
  echo "   Check logs: docker-compose logs mongodb-primary"
  exit 1
fi
