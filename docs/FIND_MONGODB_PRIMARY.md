# Find Where Your App Uses "mongodb-primary"

## The Problem

Your application (`dev-w3ky`) is still trying to connect to `mongodb-primary`, which only works inside Docker. You need to find where this is hardcoded and replace it.

## Where to Look

### 1. Environment Variables

Check all your `.env` files:

```bash
# Search for mongodb-primary in all env files
grep -r "mongodb-primary" .env* .env.local* .env.production* .env.development* 2>/dev/null

# Or check specific files
cat .env
cat .env.local
cat .env.development
cat .env.production
```

**Look for:**
- `MONGODB_URI=...mongodb-primary...`
- `MONGO_HOST=mongodb-primary`
- `DATABASE_URL=...mongodb-primary...`
- Any connection string containing `mongodb-primary`

### 2. Application Code

Search your application codebase:

```bash
# If your app is in a different directory, navigate there first
cd /path/to/your/app

# Search for mongodb-primary
grep -r "mongodb-primary" . --exclude-dir=node_modules --exclude-dir=.next

# Search for connection strings
grep -r "MONGODB_URI\|MONGO.*URI\|mongoose.connect\|MongoClient" . --exclude-dir=node_modules --exclude-dir=.next

# Search for environment variable usage
grep -r "process.env.MONGODB\|process.env.MONGO" . --exclude-dir=node_modules --exclude-dir=.next
```

### 3. Configuration Files

Check config files:

```bash
# Next.js config
cat next.config.js
cat next.config.mjs

# Other config files
cat config/database.js
cat lib/mongodb.js
cat utils/db.js
cat db/index.js
```

### 4. Docker Compose (if app runs in Docker)

If your app runs in Docker, check its docker-compose file:

```bash
# If you have a docker-compose for your app
grep -r "mongodb-primary" docker-compose*.yaml docker-compose*.yml
```

## Common Places to Check

### Next.js / Node.js

1. **`.env.local`** or **`.env`**:
   ```bash
   MONGODB_URI=mongodb://user:pass@mongodb-primary:27017/...
   ```

2. **`lib/mongodb.js`** or **`lib/db.js`**:
   ```javascript
   const uri = 'mongodb://user:pass@mongodb-primary:27017/...';
   ```

3. **`config/database.js`**:
   ```javascript
   module.exports = {
     uri: 'mongodb://user:pass@mongodb-primary:27017/...'
   };
   ```

4. **`utils/db.js`**:
   ```javascript
   mongoose.connect('mongodb://user:pass@mongodb-primary:27017/...');
   ```

## Quick Fix Script

Run this in your application directory to find all occurrences:

```bash
#!/bin/bash
# find-mongodb-primary.sh

echo "=== Searching for 'mongodb-primary' ==="
echo ""

echo "1. Environment files:"
grep -r "mongodb-primary" .env* .env.local* 2>/dev/null || echo "   No matches in .env files"
echo ""

echo "2. JavaScript/TypeScript files:"
grep -r "mongodb-primary" --include="*.js" --include="*.ts" --include="*.jsx" --include="*.tsx" . --exclude-dir=node_modules --exclude-dir=.next 2>/dev/null | head -20
echo ""

echo "3. Configuration files:"
find . -name "*.config.*" -o -name "config.*" | xargs grep -l "mongodb-primary" 2>/dev/null || echo "   No matches in config files"
echo ""

echo "4. Docker compose files:"
find . -name "docker-compose*.yaml" -o -name "docker-compose*.yml" | xargs grep -l "mongodb-primary" 2>/dev/null || echo "   No matches in docker-compose files"
```

## What to Replace

### Replace This:
```bash
# In .env files
MONGODB_URI=mongodb://user:pass@mongodb-primary:27017/...
MONGO_HOST=mongodb-primary
```

### With This:
```bash
# Same server
MONGODB_URI=mongodb://user:pass@localhost:27017/...
MONGO_HOST=localhost

# Or use separate variables (recommended)
MONGODB_HOST=localhost
MONGODB_PORT=27017
MONGODB_USERNAME=rbdbuser
MONGODB_PASSWORD=yourpassword
MONGODB_DATABASE=w3kyc
MONGODB_REPLICA_SET=rs0
```

## After Finding and Fixing

1. **Update the connection string** to use `localhost` or your server IP
2. **Restart your application**
3. **Verify it works**

## Still Can't Find It?

If you can't find it, the connection string might be:
- Built dynamically in code
- Set in a build-time environment variable
- Hardcoded in a compiled file
- Set in your deployment platform (Vercel, Railway, etc.)

Check your deployment platform's environment variables!
