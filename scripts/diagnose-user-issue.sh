#!/bin/bash
# Diagnostic script to check MongoDB user issue

set -e

echo "=========================================="
echo "MongoDB User Issue Diagnostic"
echo "=========================================="
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

echo "✓ Environment variables found"
echo "  Username: $MONGO_INITDB_ROOT_USERNAME"
echo ""

# Check if primary is running
if ! docker ps | grep -q "mongo-primary"; then
  echo "✗ mongo-primary container is not running"
  echo "  Start it with: docker-compose up -d mongodb-primary"
  exit 1
fi

echo "✓ mongo-primary container is running"
echo ""

# Check MongoDB process
if ! docker exec mongo-primary pgrep -x mongod > /dev/null; then
  echo "✗ mongod process is not running inside container"
  exit 1
fi

echo "✓ mongod process is running"
echo ""

# Check if we can connect without auth
echo "Testing connection without authentication..."
if docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  echo "✓ Can connect WITHOUT authentication"
  AUTH_REQUIRED=false
else
  echo "✗ Cannot connect WITHOUT authentication"
  AUTH_REQUIRED=true
fi
echo ""

# Check if keyFile is in command
echo "Checking MongoDB command..."
MONGOD_CMD=$(docker inspect mongo-primary --format='{{range .Args}}{{.}} {{end}}' 2>/dev/null || docker exec mongo-primary ps aux | grep mongod | grep -v grep || echo "")
if echo "$MONGOD_CMD" | grep -q "keyFile\|keyfile"; then
  echo "✗ keyFile is present in MongoDB command (authentication required)"
  KEYFILE_PRESENT=true
else
  echo "✓ keyFile is NOT present in MongoDB command"
  KEYFILE_PRESENT=false
fi
echo ""

# Check if data directory exists
if [ -d "db_data_primary" ] && [ "$(ls -A db_data_primary 2>/dev/null)" ]; then
  echo "✓ db_data_primary directory exists and is not empty"
  DATA_EXISTS=true
else
  echo "✗ db_data_primary directory is empty or doesn't exist"
  DATA_EXISTS=false
fi
echo ""

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Authentication required: $AUTH_REQUIRED"
echo "keyFile in command: $KEYFILE_PRESENT"
echo "Data exists: $DATA_EXISTS"
echo ""

if [ "$AUTH_REQUIRED" = "true" ] && [ "$KEYFILE_PRESENT" = "true" ]; then
  echo "🔴 PROBLEM IDENTIFIED:"
  echo "   MongoDB requires authentication (keyFile is set)"
  echo "   But the user doesn't exist"
  echo ""
  echo "SOLUTION:"
  echo "   1. Stop MongoDB"
  echo "   2. Temporarily remove --keyFile from command"
  echo "   3. Start MongoDB without keyFile"
  echo "   4. Create the user"
  echo "   5. Stop MongoDB"
  echo "   6. Restore --keyFile and restart"
  echo ""
  echo "   Run: ./scripts/fix-user-manual.sh"
  exit 1
fi

if [ "$AUTH_REQUIRED" = "false" ] && [ "$KEYFILE_PRESENT" = "false" ]; then
  echo "✓ MongoDB is running without authentication"
  echo "   You can create the user now"
  echo ""
  echo "   Run: ./scripts/create-user-now.sh"
  exit 0
fi

echo "Status unclear. Check the output above."
