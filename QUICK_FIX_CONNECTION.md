# Quick Fix: Connection Error

## Your Error

```
getaddrinfo ENOTFOUND mongodb-primary
```

## The Problem

Your app is using `mongodb-primary` which only works **inside Docker**. Your app runs **outside Docker**.

## The Fix

Change your connection string from:
```
mongodb://rbdbuser:password@mongodb-primary:27017/...
```

To:
```
mongodb://rbdbuser:password@localhost:27017/...
```

Or if app is on different server:
```
mongodb://rbdbuser:password@YOUR_SERVER_IP:27017/...
```

## Full Connection String

### Same Server (localhost)
```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Different Server (use IP)
```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@YOUR_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

## Where to Change

1. **Environment variable** (`.env`, `.env.local`, etc.)
2. **Application config file**
3. **Restart your app** after changing

## Test It

```bash
# Test connection
mongosh "mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

If this works, your app will work too!
