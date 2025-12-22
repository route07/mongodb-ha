# Understanding MongoDB Primary Failover

## What Happens When Primary Goes Down

When the primary MongoDB container stops:

1. **Containers don't stop** - Only the primary container stops, secondaries keep running ✅
2. **Replica set detects failure** - Secondaries notice primary is unreachable
3. **Election happens** - One secondary is elected as new primary (usually takes 10-30 seconds)
4. **Your app should reconnect** - MongoDB driver automatically finds the new primary

## Testing Failover

### Step 1: Check Current Status

```bash
cd ~/ha-mongodb
./scripts/check-replica-set-status.sh
```

Note which node is PRIMARY.

### Step 2: Stop Primary Container

```bash
docker-compose stop mongodb-primary
# or
docker stop mongo-primary
```

### Step 3: Wait for Election (30-60 seconds)

```bash
sleep 30
```

### Step 4: Check New Primary

```bash
# Connect to any running secondary
docker exec mongodb-secondary-1 mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"
```

You should see one of the secondaries is now PRIMARY.

### Step 5: Restart Original Primary

```bash
docker-compose start mongodb-primary
# or
docker start mongo-primary
```

After it starts, it will:
- Join the replica set as a SECONDARY
- Sync data from the current primary
- Be available for future elections

## Important Notes

### Your App Should Handle This Automatically

If your connection string uses:
- `localhost` or server IP (not `mongodb-primary`)
- `replicaSet=rs0` parameter
- Proper timeouts (`serverSelectionTimeoutMS: 30000`)

Then your app will:
1. Connect to initial host
2. Discover replica set members
3. Automatically find and connect to the PRIMARY
4. Reconnect to new PRIMARY if current one fails

### Scripts Need to Connect to Any Node

The status check script now connects to any available node (not just `mongo-primary`), so it works even when primary is down.

## Common Issues

### Issue 1: No Primary After Failover

**Symptom**: All nodes show as SECONDARY after primary stops

**Causes**:
- Not enough healthy nodes for quorum (need majority)
- Network issues between nodes
- Election timeout too short

**Fix**: Wait longer (up to 60 seconds), or check network connectivity

### Issue 2: App Can't Connect After Failover

**Symptom**: App times out trying to connect

**Causes**:
- Connection string uses `mongodb-primary` hostname (doesn't resolve)
- Timeout too short
- App not reconnecting

**Fix**:
1. Use `localhost` or server IP in connection string
2. Increase `serverSelectionTimeoutMS` to 30000
3. Add `readPreference: 'primaryPreferred'`

### Issue 3: Original Primary Doesn't Rejoin

**Symptom**: After restarting original primary, it doesn't sync

**Fix**: Usually resolves automatically. If not, check logs:
```bash
docker logs mongo-primary | tail -50
```

## Best Practices

1. **Always use `replicaSet=rs0`** in connection string (enables automatic failover)
2. **Use resolvable hostnames** (`localhost`, IP, or hostnames in `/etc/hosts`)
3. **Set appropriate timeouts** (30 seconds for server selection)
4. **Use `readPreference: 'primaryPreferred'`** (allows reading from secondary if needed)
5. **Monitor replica set status** regularly

## Summary

- ✅ Containers don't stop when primary goes down
- ✅ Replica set automatically elects new primary
- ✅ Your app should reconnect automatically (if configured correctly)
- ✅ Original primary rejoins as secondary when restarted
- ✅ This is normal MongoDB HA behavior!
