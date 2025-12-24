# Reading from Secondary Nodes

## Can Clients Interact with Secondaries?

**Short Answer**: Yes, but with important limitations:

- ✅ **Reads**: Clients CAN read from secondaries (with proper configuration)
- ❌ **Writes**: Clients CANNOT write to secondaries (only primary accepts writes)

## Read Operations from Secondaries

### Why Read from Secondaries?

1. **Read Scaling**: Distribute read load across multiple nodes
2. **Reduced Primary Load**: Offload read queries from the primary
3. **Geographic Distribution**: Read from nearest secondary
4. **Analytics/Reporting**: Run heavy queries without impacting primary performance

### How to Configure

#### Option 1: Using Read Preference (Recommended)

Configure your client to prefer or require reading from secondaries:

**Connection String:**
```bash
mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&readPreference=secondaryPreferred&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Read Preference Options:**
- `primary` (default) - Only read from primary
- `primaryPreferred` - Prefer primary, fallback to secondary if primary unavailable
- `secondary` - Only read from secondaries (fails if no secondary available)
- `secondaryPreferred` - Prefer secondaries, fallback to primary if no secondary available
- `nearest` - Read from node with lowest latency

#### Option 2: Direct Connection to Secondary

You can connect directly to a secondary node (bypassing replica set discovery):

```bash
# Connect directly to secondary-1
mongosh "mongodb://user:pass@localhost:27018/db?directConnection=true&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

**Note**: With `directConnection=true`, you bypass replica set discovery and connect only to that specific node.

### Code Examples

#### Node.js (Mongoose)

```javascript
const mongoose = require('mongoose');

// Option 1: Read preference in connection string
const uri = 'mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&readPreference=secondaryPreferred&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin';

mongoose.connect(uri);

// Option 2: Read preference in options
mongoose.connect(uri, {
  readPreference: 'secondaryPreferred', // Prefer secondaries for reads
  readPreferenceTags: [] // Optional: filter by tags
});

// Option 3: Per-query read preference
const users = await User.find({}).read('secondary'); // Read from secondary
```

#### Node.js (Native Driver)

```javascript
const { MongoClient } = require('mongodb');

const uri = 'mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin';

const client = new MongoClient(uri, {
  readPreference: 'secondaryPreferred'
});

await client.connect();

// All queries will prefer secondaries
const db = client.db('mydb');
const collection = db.collection('users');

// Or specify per-query
const users = await collection.find({}).readPreference('secondary').toArray();
```

#### Python (pymongo)

```python
from pymongo import MongoClient, ReadPreference

# Option 1: Read preference in connection string
uri = "mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&readPreference=secondaryPreferred&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"

client = MongoClient(uri)

# Option 2: Read preference in client options
client = MongoClient(
    uri,
    read_preference=ReadPreference.SECONDARY_PREFERRED
)

# Option 3: Per-query read preference
db = client['mydb']
collection = db['users']
users = collection.find({}).read_preference(ReadPreference.SECONDARY)
```

## Write Operations

### ❌ Writes Can ONLY Go to Primary

**Important**: MongoDB replica sets have a **single-primary architecture**. Only the primary node accepts write operations.

If you try to write to a secondary:
- The operation will **fail** with an error
- Error: `"not master"` or `"not primary"`
- You must write to the primary

### Example of Write Failure

```javascript
// This will FAIL if connected to secondary
try {
  await collection.insertOne({ name: 'John' });
} catch (error) {
  // Error: "not master" or "not primary"
  console.error('Write failed:', error.message);
}
```

### Solution: Use Primary for Writes

```javascript
// Always use primary for writes
const writeClient = new MongoClient(uri, {
  readPreference: 'primary' // Explicitly use primary for writes
});

// Or use default (primary is default)
const writeClient = new MongoClient(uri);
```

## Use Cases

### 1. Read Scaling (Separate Read/Write Connections)

```javascript
// Write connection (always uses primary)
const writeClient = new MongoClient(uri, {
  readPreference: 'primary'
});

// Read connection (uses secondaries)
const readClient = new MongoClient(uri, {
  readPreference: 'secondaryPreferred'
});

// Use writeClient for inserts/updates
await writeClient.db('mydb').collection('users').insertOne({ name: 'John' });

// Use readClient for queries
const users = await readClient.db('mydb').collection('users').find({}).toArray();
```

### 2. Analytics/Reporting (Read-Only from Secondaries)

```javascript
// Heavy analytics queries on secondary
const analyticsClient = new MongoClient(uri, {
  readPreference: 'secondary' // Only read from secondaries
});

// Run heavy aggregation queries
const report = await analyticsClient.db('mydb').collection('orders')
  .aggregate([
    { $group: { _id: '$status', count: { $sum: 1 } } }
  ])
  .toArray();
```

### 3. Geographic Distribution

If you have secondaries in different regions:

```javascript
// Read from nearest secondary
const client = new MongoClient(uri, {
  readPreference: 'nearest' // Automatically selects lowest latency node
});
```

## Important Considerations

### 1. Replication Lag

**Stale Reads**: Data on secondaries may be slightly behind the primary (replication lag).

- Typical lag: < 1 second
- Can be higher during heavy write loads
- Check replication lag: `rs.printSlaveReplicationInfo()`

**When Stale Reads Matter:**
- ❌ Financial transactions (use primary)
- ❌ Real-time data (use primary)
- ✅ Analytics/reporting (stale data OK)
- ✅ Read-heavy workloads (stale data usually OK)

### 2. Consistency Levels

MongoDB provides different consistency guarantees:

- **Strong Consistency** (primary): Always up-to-date
- **Eventual Consistency** (secondaries): May be slightly stale

### 3. Secondary Availability

If you use `readPreference: 'secondary'`:
- Query will **fail** if no secondary is available
- Use `secondaryPreferred` to fallback to primary

### 4. Connection String Requirements

Even when reading from secondaries, you should:
- ✅ Include all replica set members in connection string
- ✅ Include `replicaSet=rs0` parameter
- ✅ Let driver discover and route to appropriate node

**Example:**
```bash
# ✅ GOOD - Includes all members, driver routes automatically
mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&readPreference=secondaryPreferred&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin

# ⚠️ OK - Direct connection to one secondary (bypasses discovery)
mongodb://user:pass@localhost:27018/db?directConnection=true&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

## Testing Secondary Reads

### Test 1: Verify Read from Secondary

```bash
# Connect to secondary directly
mongosh "mongodb://user:pass@localhost:27018/db?directConnection=true&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"

# Try to read (should work)
db.users.find().limit(1)

# Try to write (should fail)
db.users.insertOne({ test: 'data' })
# Error: "not master"
```

### Test 2: Verify Read Preference

```javascript
const { MongoClient } = require('mongodb');

const uri = 'mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin';

const client = new MongoClient(uri, {
  readPreference: 'secondary'
});

await client.connect();

// Check which node we're reading from
const result = await client.db('admin').command({ isMaster: 1 });
console.log('Reading from:', result.primary || 'secondary');
```

## Summary

| Operation | Primary | Secondary |
|-----------|---------|-----------|
| **Reads** | ✅ Yes (default) | ✅ Yes (with `readPreference`) |
| **Writes** | ✅ Yes (only option) | ❌ No (will fail) |
| **Direct Connection** | ✅ Yes | ✅ Yes (reads only) |

**Best Practice:**
- Use **primary** for all writes
- Use **secondaryPreferred** for reads to distribute load
- Use **secondary** for analytics/reporting (accepts stale data)
- Always include all replica set members in connection string
