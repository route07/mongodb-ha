# Manual Fix for Missing MongoDB User (Remote Server)

If you're getting `Command createUser requires authentication` error, follow these steps:

## Quick Diagnostic

First, run the diagnostic script to understand the issue:

```bash
./scripts/diagnose-user-issue.sh
```

This will tell you exactly what's wrong.

## Manual Fix Steps

### Option 1: Automated Script (Recommended)

Run the automated fix script:

```bash
./scripts/fix-user-manual.sh
```

This script will:
1. Stop MongoDB
2. Temporarily remove `--keyFile` (disables auth requirement)
3. Start MongoDB without auth
4. Create the user
5. Restore configuration
6. Restart with auth enabled

### Option 2: Manual Steps

If the script doesn't work, do it manually:

#### Step 1: Stop MongoDB

```bash
docker-compose stop mongodb-primary mongodb-secondary-1 mongodb-secondary-2
```

#### Step 2: Edit docker-compose.yaml

Temporarily comment out or remove the `--keyFile` line from the `mongodb-primary` service:

```yaml
# Find this section:
mongodb-primary:
  # ... other config ...
  command: >
    mongod
    --replSet ${REPLICA_SET_NAME:-rs0}
    --keyFile /etc/mongo/ssl/keyfile    # <-- COMMENT THIS LINE
    --tlsMode requireTLS
    # ... rest of command ...
```

Change to:

```yaml
mongodb-primary:
  # ... other config ...
  command: >
    mongod
    --replSet ${REPLICA_SET_NAME:-rs0}
    # --keyFile /etc/mongo/ssl/keyfile    # <-- COMMENTED OUT
    --tlsMode requireTLS
    # ... rest of command ...
```

#### Step 3: Start MongoDB without keyFile

```bash
docker-compose up -d mongodb-primary
```

Wait for it to start (check logs):

```bash
docker-compose logs -f mongodb-primary
```

Wait until you see MongoDB is ready (usually takes 10-30 seconds).

#### Step 4: Create the user

```bash
# Make sure .env has your credentials
source .env

docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "
    db.getSiblingDB('admin').createUser({
      user: '$MONGO_INITDB_ROOT_USERNAME',
      pwd: '$MONGO_INITDB_ROOT_PASSWORD',
      roles: [{ role: 'root', db: 'admin' }]
    })
  "
```

You should see: `{ ok: 1 }`

#### Step 5: Verify user was created

```bash
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

You should see: `{ ok: 1 }`

#### Step 6: Stop MongoDB

```bash
docker-compose stop mongodb-primary
```

#### Step 7: Restore docker-compose.yaml

Uncomment the `--keyFile` line you commented out in Step 2.

#### Step 8: Start everything

```bash
docker-compose up -d
```

#### Step 9: Verify everything works

```bash
# Check primary
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

## What to Check Manually

### 1. Check if MongoDB is running

```bash
docker ps | grep mongo-primary
docker exec mongo-primary ps aux | grep mongod
```

### 2. Check MongoDB command

```bash
docker inspect mongo-primary --format='{{range .Args}}{{.}} {{end}}'
```

Look for `--keyFile` - if it's there, MongoDB requires authentication.

### 3. Check if you can connect without auth

```bash
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "db.adminCommand('ping')"
```

- If this works: MongoDB allows unauthenticated connections (you can create user)
- If this fails: MongoDB requires authentication (need to remove keyFile first)

### 4. Check environment variables

```bash
cat .env | grep MONGO_INITDB
```

Make sure `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` are set.

### 5. Check MongoDB logs

```bash
docker-compose logs mongodb-primary | tail -50
```

Look for:
- Authentication errors
- KeyFile errors
- User creation messages

### 6. Check data directory

```bash
ls -la db_data_primary/
```

If this directory exists and has files, MongoDB was initialized before. The user should have been created during initialization, but if it wasn't, you need to create it manually.

## Common Issues

### Issue: "Cannot connect without authentication"

**Cause:** `--keyFile` is set in the MongoDB command, which requires authentication.

**Solution:** Temporarily remove `--keyFile` from docker-compose.yaml, start MongoDB, create user, then restore `--keyFile`.

### Issue: "User already exists"

**Cause:** The user was created but authentication still fails.

**Solution:** 
1. Check the username/password in `.env` matches what you're using
2. Verify the user exists: `docker exec mongo-primary mongosh --tls --tlsAllowInvalidCertificates --tlsCAFile /etc/mongo/ssl/ca.crt --eval "db.getSiblingDB('admin').getUsers()"`
3. Try resetting the password

### Issue: "MongoDB won't start without keyFile"

**Cause:** This shouldn't happen - MongoDB should start fine without keyFile, it just won't require authentication.

**Solution:** Check logs for other errors: `docker-compose logs mongodb-primary`

## Still Having Issues?

1. Run diagnostic: `./scripts/diagnose-user-issue.sh`
2. Check all logs: `docker-compose logs > all-logs.txt`
3. Verify your `.env` file has correct values
4. Try the complete reset (⚠️ deletes all data):
   ```bash
   docker-compose down
   rm -rf db_data_primary/ db_data_secondary1/ db_data_secondary2/
   docker-compose up -d
   ```
