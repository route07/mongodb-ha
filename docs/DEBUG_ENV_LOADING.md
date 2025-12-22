# Debug: Environment Variable Not Loading

## The Problem

Your `.env.local` has `localhost` but the app still tries to connect to `mongodb-primary`. This means the environment variable isn't being loaded correctly.

## Quick Checks

### 1. Verify .env.local is in the Right Place

For Next.js, `.env.local` must be in the **root** of your project (same level as `package.json`):

```bash
cd /path/to/your/app
ls -la .env.local
# Should show the file exists

# Check it's in the right location
pwd
# Should be your app root, not a subdirectory
```

### 2. Check for Multiple .env Files

Next.js loads env files in this order (later ones override earlier):
1. `.env`
2. `.env.local`
3. `.env.development` / `.env.production`
4. `.env.development.local` / `.env.production.local`

**Check all of them:**

```bash
# List all env files
ls -la .env*

# Check each one for MONGODB_URI
grep MONGODB_URI .env* 2>/dev/null
```

**If you find `mongodb-primary` in any `.env` file, that's the problem!**

### 3. Check Build-Time vs Runtime

Next.js has two types of env variables:
- **Server-side only**: `MONGODB_URI` (default)
- **Client-side**: `NEXT_PUBLIC_*` prefix

If `MONGODB_URI` is set at **build time** (e.g., in Vercel, Railway, etc.), it overrides `.env.local`.

**Check your deployment platform:**
- Vercel: Settings → Environment Variables
- Railway: Variables tab
- Docker: Environment variables in docker-compose or Dockerfile
- System: `printenv | grep MONGODB`

### 4. Restart Your Dev Server

After changing `.env.local`, you **must restart**:

```bash
# Stop the dev server (Ctrl+C)
# Then restart
npm run dev
# or
yarn dev
# or
pnpm dev
```

### 5. Add Debug Logging

Temporarily add this to `src/lib/mongodb.ts` to see what's actually being loaded:

```typescript
const MONGODB_URI = process.env.MONGODB_URI!;

// Add this debug line
console.log('[DEBUG] MONGODB_URI:', MONGODB_URI ? MONGODB_URI.replace(/:[^:@]+@/, ':****@') : 'NOT SET');
console.log('[DEBUG] Contains mongodb-primary:', MONGODB_URI?.includes('mongodb-primary'));

if (!MONGODB_URI) {
  throw new Error('Please define the MONGODB_URI environment variable inside .env.local');
}
```

This will show you what the app is actually seeing.

## Common Issues

### Issue 1: .env.local Not Loaded

**Symptom**: App doesn't see the variable at all

**Fix**:
1. Make sure `.env.local` is in project root
2. Restart dev server
3. Check file permissions: `chmod 644 .env.local`

### Issue 2: Another .env File Overrides

**Symptom**: `.env.local` has `localhost` but app uses `mongodb-primary`

**Fix**:
```bash
# Find which file has mongodb-primary
grep -r "mongodb-primary" .env* 2>/dev/null

# Remove or fix that file
```

### Issue 3: Build-Time Variable Set

**Symptom**: Works locally but fails in production/deployment

**Fix**: Check your deployment platform's environment variables and update them

### Issue 4: Cached Build

**Symptom**: Changes to `.env.local` don't take effect

**Fix**:
```bash
# Clear Next.js cache
rm -rf .next

# Restart
npm run dev
```

## Step-by-Step Fix

1. **Check all .env files:**
   ```bash
   grep MONGODB_URI .env* 2>/dev/null
   ```

2. **If you find `mongodb-primary` anywhere, replace it:**
   ```bash
   # Edit the file
   nano .env  # or whatever file has it
   # Change mongodb-primary to localhost
   ```

3. **Add debug logging** (see above)

4. **Clear cache and restart:**
   ```bash
   rm -rf .next
   npm run dev
   ```

5. **Check the console output** - it should show `localhost`, not `mongodb-primary`

6. **If still showing `mongodb-primary`**, check:
   - Deployment platform env vars
   - System environment variables
   - Docker environment (if using Docker)

## Verify It's Fixed

After fixing, you should see in your app logs:
```
[DEBUG] MONGODB_URI: mongodb://rbdbuser:****@localhost:27017/...
[DEBUG] Contains mongodb-primary: false
```

And the connection should work!
