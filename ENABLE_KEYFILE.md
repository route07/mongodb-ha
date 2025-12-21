# Enable keyFile for Remote Connections

## Why Enable keyFile?

Since you're connecting from remote servers, **keyFile should be enabled** for better security:

- ✅ Prevents unauthorized MongoDB nodes from joining your replica set
- ✅ Adds security layer for inter-node communication
- ✅ Best practice for production with remote access
- ✅ Your user already exists, so it will work

## Quick Enable Steps

### 1. Verify keyFile Exists

```bash
cd ~/ha-mongodb
ls -la tls-certs/keyfile

# If not exists, generate it
./scripts/generate-keyfile.sh
```

### 2. Verify User Works

```bash
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

**Expected**: `{ ok: 1 }`

### 3. keyFile is Already Enabled

The `docker-compose.yaml` has been updated to include `--keyFile` in all MongoDB services.

### 4. Restart Services

```bash
docker-compose restart

# Wait for services to start
sleep 20
```

### 5. Verify Everything Works

```bash
# Check all containers are healthy
docker-compose ps

# Check replica set status
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"

# Check mongo-admin
docker-compose logs mongo-admin | tail -10
```

## What keyFile Protects

**Without keyFile**:
- Remote clients: ✅ Protected (user auth)
- Inter-node: ⚠️ Not protected (any node could join)

**With keyFile**:
- Remote clients: ✅ Protected (user auth)
- Inter-node: ✅ Protected (keyFile required)

## Your Connection String (Unchanged)

Your connection string for remote clients remains the same:

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@YOUR_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

keyFile doesn't affect how clients connect - it only affects how MongoDB nodes authenticate with each other.

## If Issues Occur

If services fail to start after enabling keyFile:

1. **Check keyFile exists**: `ls -la tls-certs/keyfile`
2. **Check logs**: `docker-compose logs mongodb-primary`
3. **Verify permissions**: Should be 600
4. **Regenerate if needed**: `./scripts/generate-keyfile.sh`

## Summary

✅ keyFile is now enabled in docker-compose.yaml  
✅ Restart services to apply  
✅ Your remote connections will work the same  
✅ Inter-node communication is now more secure
