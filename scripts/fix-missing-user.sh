#!/bin/bash
# Quick fix script for missing MongoDB user
# Run this on the remote server to fix the "UserNotFound" error

set -e

echo "=========================================="
echo "MongoDB User Fix Script"
echo "=========================================="
echo ""

# Check if .env exists
if [ ! -f .env ]; then
  echo "Error: .env file not found"
  echo "Please create .env file with MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD"
  exit 1
fi

# Source .env file
export $(grep -v '^#' .env | xargs)

if [ -z "$MONGO_INITDB_ROOT_USERNAME" ] || [ -z "$MONGO_INITDB_ROOT_PASSWORD" ]; then
  echo "Error: MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD must be set in .env"
  exit 1
fi

echo "Username: $MONGO_INITDB_ROOT_USERNAME"
echo ""

# Check if containers are running
if ! docker-compose ps | grep -q "mongo-primary.*Up"; then
  echo "Error: MongoDB primary container is not running"
  echo "Please start containers first: docker-compose up -d"
  exit 1
fi

echo "Step 1: Checking if user exists..."
echo ""

# Try to connect with auth
if docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  echo "✓ User '$MONGO_INITDB_ROOT_USERNAME' exists and authentication works!"
  echo "No action needed."
  exit 0
fi

echo "User not found or authentication failed."
echo ""

# Check if we can connect without auth
echo "Step 2: Checking if MongoDB allows unauthenticated connections..."
if ! docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  echo "✗ Cannot connect to MongoDB without authentication"
  echo ""
  echo "This means MongoDB requires authentication but the user doesn't exist."
  echo ""
  echo "Solution: You need to clear the data directories and start fresh:"
  echo ""
  echo "  docker-compose down"
  echo "  rm -rf db_data_primary/ db_data_secondary1/ db_data_secondary2/"
  echo "  docker-compose up -d"
  echo ""
  echo "⚠️  WARNING: This will delete all existing data!"
  exit 1
fi

echo "✓ MongoDB allows unauthenticated connections"
echo ""

echo "Step 3: Creating root user..."
echo ""

# Create the user
docker exec mongo-primary mongosh --tls \
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
      print('SUCCESS: User created');
    } catch (e) {
      if (e.code === 51003 || e.message.includes('already exists')) {
        print('INFO: User already exists');
      } else {
        print('ERROR: ' + e.message);
        throw e;
      }
    }
  " 2>&1

if [ $? -ne 0 ]; then
  echo "✗ Failed to create user"
  exit 1
fi

echo ""
echo "Step 4: Verifying user creation..."
echo ""

# Verify the user works
if docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  echo "✓ User created successfully and authentication works!"
  echo ""
  echo "You may need to restart the containers:"
  echo "  docker-compose restart"
  exit 0
else
  echo "✗ User created but authentication still fails"
  echo "Please check your .env file and restart containers:"
  echo "  docker-compose restart"
  exit 1
fi
