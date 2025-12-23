# Oplog Warnings Explained

## The Warning

```
NamespaceNotFound: Collection [local.oplog.rs] not found
```

## What This Means

This is a **normal warning** (not an error) that appears when:

1. ✅ MongoDB node is running
2. ✅ Node is part of a replica set
3. ✅ Node is in **STARTUP** or **STARTUP2** state (initial sync)
4. ⚠️ Oplog collection doesn't exist yet (will be created during sync)

## Why It Happens

- MongoDB's monitoring system tries to query the oplog for statistics
- The oplog (`local.oplog.rs`) is created during initial sync
- Until sync completes, the collection doesn't exist → warning appears
- **This is expected behavior** - not a problem!

## When It Stops

The warnings will stop once:
- ✅ Initial sync completes
- ✅ Oplog collection is created
- ✅ Node transitions to SECONDARY state

## What to Check

### 1. Check Replica Set Status

On your **primary server**:

```bash
cd ~/ha-mongodb
source .env

docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    var status = rs.status();
    status.members.forEach(function(m) {
      print(m.name + ': ' + m.stateStr);
      if (m.stateStr === 'STARTUP' || m.stateStr === 'STARTUP2') {
        print('  → Node is syncing (this is normal)');
      }
      if (m.optimeDate) {
        var lag = new Date() - m.optimeDate;
        print('  → Replication lag: ' + Math.round(lag/1000) + ' seconds');
      }
    });
  "
```

### 2. Check Node State

Look for these states:

- **STARTUP** - Node is starting up, initializing
- **STARTUP2** - Node is in initial sync (copying data from primary)
- **SECONDARY** - ✅ Node is synced and healthy
- **PRIMARY** - Node is the primary
- **DOWN** - ❌ Node is unreachable
- **UNREACHABLE** - ❌ Node can't be reached

### 3. Monitor Sync Progress

The warnings will continue until the node reaches **SECONDARY** state. This can take:
- **Small databases**: 1-5 minutes
- **Large databases**: 10 minutes to several hours (depending on data size)

## Is This a Problem?

**No!** This is normal behavior. The warnings indicate:

✅ Node is running  
✅ Node is trying to sync  
✅ Replica set communication is working  

## When to Worry

Only worry if:

1. **Node stays in STARTUP2 for hours** (very large database - this is normal)
2. **Node shows as DOWN or UNREACHABLE** (network/firewall issue)
3. **Node shows errors** (not warnings) in logs
4. **Replication lag keeps increasing** (sync is failing)

## What to Do

### Option 1: Wait (Recommended)

Just wait for initial sync to complete. The warnings will stop automatically.

### Option 2: Check Sync Progress

```bash
# On new server
docker exec mongo-secondary-2 mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    var status = rs.status();
    var me = status.members.find(m => m.self);
    if (me) {
      print('State: ' + me.stateStr);
      if (me.stateStr === 'STARTUP2') {
        print('Initial sync in progress...');
        print('This can take time depending on database size.');
      } else if (me.stateStr === 'SECONDARY') {
        print('✅ Sync complete! Node is healthy.');
      }
    }
  "
```

### Option 3: Check for Real Errors

Look for actual errors (not warnings) in logs:

```bash
# On new server
docker logs mongo-secondary-2 2>&1 | grep -i "error" | grep -v "oplog.rs"
```

If you see errors (not warnings), those need to be fixed.

## Summary

- ✅ **Warnings are normal** during initial sync
- ✅ **Node is working correctly** - just syncing data
- ✅ **Warnings will stop** when sync completes
- ⏳ **Be patient** - initial sync takes time
- 🔍 **Check replica set status** to see actual state

The fact that you're seeing these warnings means the node is **working and syncing** - which is exactly what you want!
