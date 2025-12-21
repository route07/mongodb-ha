#!/bin/bash
# Create MongoDB user when MongoDB is running without authentication

set -e

if [ ! -f .env ]; then
  echo "Error: .env file not found"
  exit 1
fi

export $(grep -v '^#' .env | xargs)

if [ -z "$MONGO_INITDB_ROOT_USERNAME" ] || [ -z "$MONGO_INITDB_ROOT_PASSWORD" ]; then
  echo "Error: MONGO_INITDB_ROOT_USERNAME or MONGO_INITDB_ROOT_PASSWORD not set"
  exit 1
fi

echo "Creating user: $MONGO_INITDB_ROOT_USERNAME"

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

echo ""
echo "Verifying..."
if docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')" \
  --quiet \
  > /dev/null 2>&1; then
  echo "✓ User created and verified!"
else
  echo "✗ User creation failed or authentication doesn't work"
  exit 1
fi
