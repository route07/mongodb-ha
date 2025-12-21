#!/bin/bash
# Initialize MongoDB root user if it doesn't exist
# This runs after MongoDB has started

set -e

MONGO_USERNAME=${MONGO_INITDB_ROOT_USERNAME}
MONGO_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD}
HOST=${1:-localhost}
PORT=${2:-27017}
MAX_RETRIES=30
RETRY_INTERVAL=2

if [ -z "$MONGO_USERNAME" ] || [ -z "$MONGO_PASSWORD" ]; then
  echo "Error: MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD must be set"
  exit 1
fi

echo "Waiting for MongoDB to be ready..."

# Wait for MongoDB to be ready
for i in $(seq 1 $MAX_RETRIES); do
  if mongosh --tls \
    --tlsAllowInvalidCertificates \
    --tlsCAFile /etc/mongo/ssl/ca.crt \
    --host "$HOST:$PORT" \
    --eval "db.adminCommand('ping')" \
    --quiet \
    > /dev/null 2>&1; then
    echo "✓ MongoDB is ready"
    break
  fi
  if [ $i -eq $MAX_RETRIES ]; then
    echo "✗ MongoDB failed to become ready after $MAX_RETRIES attempts"
    exit 1
  fi
  echo "Waiting for MongoDB... (attempt $i/$MAX_RETRIES)"
  sleep $RETRY_INTERVAL
done

echo "Checking if root user exists..."

# Try with authentication first (fastest check)
if mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --host "$HOST:$PORT" \
  -u "$MONGO_USERNAME" \
  -p "$MONGO_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  echo "✓ Root user '$MONGO_USERNAME' exists and authentication works"
  echo "✓ No action needed - exiting immediately"
  exit 0
fi

# Check if user exists (try with auth first, then without)
USER_EXISTS=false

# Try without authentication to check if user exists
USER_CHECK=$(mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --host "$HOST:$PORT" \
  --quiet \
  --eval "
    try {
      const user = db.getSiblingDB('admin').getUser('$MONGO_USERNAME');
      print('EXISTS');
    } catch (e) {
      if (e.code === 11 || e.message.includes('not found') || e.message.includes('UserNotFound')) {
        print('NOT_EXISTS');
      } else {
        print('ERROR: ' + e.message);
      }
    }
  " 2>/dev/null || echo "NOT_EXISTS")

if echo "$USER_CHECK" | grep -q "EXISTS"; then
  echo "✓ Root user '$MONGO_USERNAME' exists"
  exit 0
fi

if echo "$USER_CHECK" | grep -q "ERROR"; then
  echo "⚠ Error checking user: $USER_CHECK"
  echo "Attempting to create user anyway..."
fi

echo "Root user not found. Creating root user..."

# Create the root user (without authentication)
# Temporarily disable set -e to handle errors gracefully
set +e
CREATE_RESULT=$(mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --host "$HOST:$PORT" \
  --quiet \
  --eval "
    try {
      db.getSiblingDB('admin').createUser({
        user: '$MONGO_USERNAME',
        pwd: '$MONGO_PASSWORD',
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
CREATE_EXIT_CODE=$?
set -e

if echo "$CREATE_RESULT" | grep -q "SUCCESS\|ALREADY_EXISTS"; then
  echo "✓ Root user '$MONGO_USERNAME' created successfully"
  exit 0
elif echo "$CREATE_RESULT" | grep -q "requires authentication\|authentication\|Command createUser requires"; then
  echo "⚠️  Cannot create user: MongoDB requires authentication"
  echo ""
  echo "This is a chicken-and-egg problem that cannot be fixed automatically."
  echo "You need to run the manual fix script:"
  echo ""
  echo "  ./scripts/fix-user-quick.sh"
  echo ""
  echo "Or see: MANUAL_FIX_REMOTE.md"
  echo ""
  echo "Exiting gracefully (code 0) to allow other services to start..."
  exit 0
else
  echo "✗ Failed to create root user: $CREATE_RESULT"
  exit 1
fi
