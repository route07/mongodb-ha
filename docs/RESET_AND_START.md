# Reset and Start Fresh

If you're having issues, here's how to reset everything to a clean state:

## Complete Reset (⚠️ Deletes All Data)

```bash
# Stop all containers
docker-compose down

# Remove all data directories
rm -rf db_data_primary/ db_data_secondary1/ db_data_secondary2/

# Start fresh
docker-compose up -d
```

This will:
1. Start MongoDB containers (user will be created automatically on first init)
2. Initialize replica set automatically
3. Start mongo-admin

## Verify Everything Works

```bash
# Check all containers are running
docker-compose ps

# Check replica set status
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"

# Check mongo-admin logs
docker-compose logs mongo-admin | tail -20
```

## If User Creation Fails

If MongoDB requires authentication but user doesn't exist (remote server issue):

```bash
./scripts/fix-user-quick.sh
```

Then restart:
```bash
docker-compose restart
```
