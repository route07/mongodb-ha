# Removing TLS from MongoDB Setup

## Changes Made

TLS requirements have been removed from the MongoDB configuration:

### 1. Docker Compose (`docker-compose.yaml`)

**Removed from all MongoDB services:**
- `--tlsMode requireTLS`
- `--tlsCertificateKeyFile /etc/mongo/ssl/server.pem`
- `--tlsCAFile /etc/mongo/ssl/ca.crt`
- `--tlsAllowConnectionsWithoutCertificates`

**Updated mongo-admin:**
- `MONGO_TLS: "false"` (was `"true"`)
- Removed TLS certificate file paths

### 2. Scripts Updated

**`scripts/healthcheck.sh`:**
- Removed `--tls`, `--tlsAllowInvalidCertificates`, `--tlsCAFile` flags

**`scripts/init-replica-set.sh`:**
- Removed all TLS flags from mongosh commands

## What Still Works

✅ **Replica Set** - Still works without TLS  
✅ **Authentication** - Username/password still required  
✅ **keyFile** - Still used for inter-node authentication  
✅ **All Features** - Everything works, just without encryption in transit

## Connection Strings (Updated)

### Before (with TLS):
```bash
mongodb://user:pass@localhost:27017/db?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### After (without TLS):
```bash
mongodb://user:pass@localhost:27017/db?replicaSet=rs0&authSource=admin
```

**Removed:**
- `&tls=true`
- `&tlsCAFile=./tls-certs/ca.crt`
- `&tlsAllowInvalidCertificates=true`

## Restart Services

After removing TLS:

```bash
# Restart all services
docker-compose restart

# Or restart specific services
docker-compose restart mongodb-primary mongodb-secondary-1 mongodb-secondary-2 mongo-admin
```

## Verify It Works

```bash
# Test connection (no TLS flags needed)
docker exec mongo-primary mongosh \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

Should return: `{ ok: 1 }`

## Important Notes

⚠️ **Security**: Without TLS, data is transmitted in plain text. Only use this in:
- Development environments
- Trusted internal networks
- When encryption is handled at a different layer (e.g., VPN)

✅ **For Production**: Consider re-enabling TLS for security.

## Re-enabling TLS Later

If you want to re-enable TLS:

1. Add TLS flags back to `docker-compose.yaml`
2. Update scripts to include TLS flags
3. Update connection strings to include `tls=true`
4. Restart services

## Summary

- ✅ TLS removed from MongoDB services
- ✅ Scripts updated (healthcheck, init-replica-set)
- ✅ mongo-admin updated to not use TLS
- ✅ Connection strings simplified (no TLS params needed)
- ⚠️ Data transmission is now unencrypted
