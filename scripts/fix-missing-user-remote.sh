#!/bin/bash
# Fix missing MongoDB user on remote server
# This script handles the case where MongoDB requires auth but user doesn't exist

set -e

echo "=========================================="
echo "MongoDB User Fix Script (Remote Server)"
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
PRIMARY_RUNNING=$(docker-compose ps | grep "mongo-primary" | grep -q "Up" && echo "yes" || echo "no")

if [ "$PRIMARY_RUNNING" = "no" ]; then
  echo "MongoDB primary container is not running"
  echo "Starting containers..."
  docker-compose up -d mongodb-primary
  echo "Waiting for MongoDB to start..."
  sleep 10
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
echo "Step 2: Attempting to connect without authentication..."
CAN_CONNECT_NO_AUTH=false

if docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  CAN_CONNECT_NO_AUTH=true
  echo "✓ Can connect without authentication"
else
  echo "✗ Cannot connect without authentication (MongoDB requires auth)"
fi

echo ""

if [ "$CAN_CONNECT_NO_AUTH" = "true" ]; then
  echo "Step 3: Creating root user..."
  echo ""
  
  # Create the user
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
    echo "✓ User created or already exists"
  else
    echo "✗ Failed to create user: $CREATE_RESULT"
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
    echo "Restarting containers to ensure everything is in sync..."
    docker-compose restart
    echo ""
    echo "✓ Done! Your MongoDB setup should now work correctly."
    exit 0
  else
    echo "✗ User created but authentication still fails"
    echo "This might be a timing issue. Try restarting:"
    echo "  docker-compose restart"
    exit 1
  fi
  
else
  echo "=========================================="
  echo "MongoDB requires authentication but user doesn't exist"
  echo "=========================================="
  echo ""
  echo "This is a chicken-and-egg problem:"
  echo "  - MongoDB requires authentication (keyFile is set)"
  echo "  - But the user doesn't exist"
  echo "  - So we can't authenticate to create the user"
  echo ""
  echo "Solution: We need to temporarily disable authentication"
  echo ""
  read -p "Do you want to proceed? This will temporarily stop MongoDB. (y/N): " -n 1 -r
  echo ""
  
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
  
  echo ""
  echo "Step 1: Stopping MongoDB containers..."
  docker-compose stop mongodb-primary mongodb-secondary-1 mongodb-secondary-2 2>/dev/null || true
  
  echo ""
  echo "Step 2: Creating temporary docker-compose override..."
  
  # Create a temporary override that removes keyFile (which enables auth)
  cat > docker-compose.tmp.yaml <<EOF
version: '3.8'
services:
  mongodb-primary:
    command: >
      mongod
      --replSet ${REPLICA_SET_NAME:-rs0}
      --tlsMode requireTLS
      --tlsCertificateKeyFile /etc/mongo/ssl/server.pem
      --tlsCAFile /etc/mongo/ssl/ca.crt
      --tlsAllowConnectionsWithoutCertificates
      --bind_ip_all
EOF
  
  echo ""
  echo "Step 3: Starting MongoDB without authentication..."
  docker-compose -f docker-compose.yaml -f docker-compose.tmp.yaml up -d mongodb-primary
  
  echo "Waiting for MongoDB to start..."
  sleep 15
  
  echo ""
  echo "Step 4: Creating root user..."
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
        print('SUCCESS');
      } catch (e) {
        if (e.code === 51003 || e.message.includes('already exists')) {
          print('ALREADY_EXISTS');
        } else {
          print('ERROR: ' + e.message);
          throw e;
        }
      }
    " 2>&1
  
  echo ""
  echo "Step 5: Stopping temporary setup..."
  docker-compose -f docker-compose.yaml -f docker-compose.tmp.yaml stop mongodb-primary
  
  echo ""
  echo "Step 6: Removing temporary override..."
  rm -f docker-compose.tmp.yaml
  
  echo ""
  echo "Step 7: Starting MongoDB with full configuration (with auth)..."
  docker-compose up -d
  
  echo ""
  echo "Waiting for MongoDB to start..."
  sleep 10
  
  echo ""
  echo "Step 8: Verifying user works..."
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
    echo "✓ Done! Your MongoDB setup should now work correctly."
    exit 0
  else
    echo "✗ Authentication still fails after creating user"
    echo "Please check the logs: docker-compose logs mongodb-primary"
    exit 1
  fi
fi
