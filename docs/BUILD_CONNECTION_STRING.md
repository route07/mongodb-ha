# Building MongoDB Connection String from Environment Variables

## Overview

Instead of hardcoding the full `MONGODB_URI`, you can use separate environment variables and build the connection string dynamically in your application. This makes it easy to switch between `localhost`, IP addresses, or hostnames.

## Environment Variables

Add these to your `.env` file:

```bash
# MongoDB Connection Components
MONGODB_HOST=localhost                    # Use 'localhost' for same server, IP/hostname for remote
MONGODB_PORT=27017                        # MongoDB port
MONGODB_USERNAME=rbdbuser                 # MongoDB username
MONGODB_PASSWORD=adsijeoirFgfsd092rvcsxvsdewRS  # MongoDB password
MONGODB_DATABASE=w3kyc                    # Database name
MONGODB_REPLICA_SET=rs0                   # Replica set name (if using HA)
MONGODB_TLS_CA_FILE=./tls-certs/ca.crt    # Path to CA certificate file
MONGODB_TLS_ALLOW_INVALID=true            # Allow self-signed certificates
```

## Building Connection String in Your Application

### Node.js / Next.js

```javascript
// lib/mongodb.js or config/database.js
function buildMongoURI() {
  const host = process.env.MONGODB_HOST || 'localhost';
  const port = process.env.MONGODB_PORT || '27017';
  const username = encodeURIComponent(process.env.MONGODB_USERNAME || '');
  const password = encodeURIComponent(process.env.MONGODB_PASSWORD || '');
  const database = process.env.MONGODB_DATABASE || 'w3kyc';
  const replicaSet = process.env.MONGODB_REPLICA_SET;
  const tlsCAFile = process.env.MONGODB_TLS_CA_FILE || './tls-certs/ca.crt';
  const tlsAllowInvalid = process.env.MONGODB_TLS_ALLOW_INVALID === 'true';

  // Build base URI
  let uri = `mongodb://${username}:${password}@${host}:${port}/${database}`;
  
  // Build query parameters
  const params = [];
  
  if (replicaSet) {
    params.push(`replicaSet=${replicaSet}`);
  }
  
  params.push('tls=true');
  params.push(`tlsCAFile=${tlsCAFile}`);
  
  if (tlsAllowInvalid) {
    params.push('tlsAllowInvalidCertificates=true');
  }
  
  params.push('authSource=admin');
  
  uri += '?' + params.join('&');
  
  return uri;
}

// Use it
const MONGODB_URI = buildMongoURI();
```

### TypeScript / Next.js (Type-Safe)

```typescript
// lib/mongodb.ts
interface MongoConfig {
  host: string;
  port: string;
  username: string;
  password: string;
  database: string;
  replicaSet?: string;
  tlsCAFile: string;
  tlsAllowInvalid: boolean;
}

function getMongoConfig(): MongoConfig {
  return {
    host: process.env.MONGODB_HOST || 'localhost',
    port: process.env.MONGODB_PORT || '27017',
    username: process.env.MONGODB_USERNAME || '',
    password: process.env.MONGODB_PASSWORD || '',
    database: process.env.MONGODB_DATABASE || 'w3kyc',
    replicaSet: process.env.MONGODB_REPLICA_SET,
    tlsCAFile: process.env.MONGODB_TLS_CA_FILE || './tls-certs/ca.crt',
    tlsAllowInvalid: process.env.MONGODB_TLS_ALLOW_INVALID === 'true',
  };
}

function buildMongoURI(): string {
  const config = getMongoConfig();
  const username = encodeURIComponent(config.username);
  const password = encodeURIComponent(config.password);
  
  let uri = `mongodb://${username}:${password}@${config.host}:${config.port}/${config.database}`;
  
  const params: string[] = [];
  
  if (config.replicaSet) {
    params.push(`replicaSet=${config.replicaSet}`);
  }
  
  params.push('tls=true');
  params.push(`tlsCAFile=${config.tlsCAFile}`);
  
  if (config.tlsAllowInvalid) {
    params.push('tlsAllowInvalidCertificates=true');
  }
  
  params.push('authSource=admin');
  
  return uri + '?' + params.join('&');
}

export const MONGODB_URI = buildMongoURI();
```

### Python

```python
# config/database.py
import os
from urllib.parse import quote_plus

def build_mongo_uri():
    host = os.getenv('MONGODB_HOST', 'localhost')
    port = os.getenv('MONGODB_PORT', '27017')
    username = quote_plus(os.getenv('MONGODB_USERNAME', ''))
    password = quote_plus(os.getenv('MONGODB_PASSWORD', ''))
    database = os.getenv('MONGODB_DATABASE', 'w3kyc')
    replica_set = os.getenv('MONGODB_REPLICA_SET')
    tls_ca_file = os.getenv('MONGODB_TLS_CA_FILE', './tls-certs/ca.crt')
    tls_allow_invalid = os.getenv('MONGODB_TLS_ALLOW_INVALID', 'true') == 'true'
    
    # Build base URI
    uri = f"mongodb://{username}:{password}@{host}:{port}/{database}"
    
    # Build query parameters
    params = []
    
    if replica_set:
        params.append(f"replicaSet={replica_set}")
    
    params.append("tls=true")
    params.append(f"tlsCAFile={tls_ca_file}")
    
    if tls_allow_invalid:
        params.append("tlsAllowInvalidCertificates=true")
    
    params.append("authSource=admin")
    
    uri += "?" + "&".join(params)
    
    return uri

MONGODB_URI = build_mongo_uri()
```

### Using with Mongoose (Node.js)

```javascript
// lib/mongodb.js
const mongoose = require('mongoose');

function buildMongoURI() {
  const host = process.env.MONGODB_HOST || 'localhost';
  const port = process.env.MONGODB_PORT || '27017';
  const username = encodeURIComponent(process.env.MONGODB_USERNAME || '');
  const password = encodeURIComponent(process.env.MONGODB_PASSWORD || '');
  const database = process.env.MONGODB_DATABASE || 'w3kyc';
  const replicaSet = process.env.MONGODB_REPLICA_SET;
  const tlsCAFile = process.env.MONGODB_TLS_CA_FILE || './tls-certs/ca.crt';
  const tlsAllowInvalid = process.env.MONGODB_TLS_ALLOW_INVALID === 'true';

  let uri = `mongodb://${username}:${password}@${host}:${port}/${database}`;
  
  const params = [];
  if (replicaSet) params.push(`replicaSet=${replicaSet}`);
  params.push('tls=true');
  params.push(`tlsCAFile=${tlsCAFile}`);
  if (tlsAllowInvalid) params.push('tlsAllowInvalidCertificates=true');
  params.push('authSource=admin');
  
  return uri + '?' + params.join('&');
}

const MONGODB_URI = buildMongoURI();

// Connect with Mongoose
mongoose.connect(MONGODB_URI, {
  // Additional options if needed
});

module.exports = mongoose;
```

## Usage Examples

### Local Development (Same Server)

```bash
# .env
MONGODB_HOST=localhost
MONGODB_PORT=27017
MONGODB_USERNAME=rbdbuser
MONGODB_PASSWORD=adsijeoirFgfsd092rvcsxvsdewRS
MONGODB_DATABASE=w3kyc
MONGODB_REPLICA_SET=rs0
MONGODB_TLS_CA_FILE=./tls-certs/ca.crt
MONGODB_TLS_ALLOW_INVALID=true
```

**Result:**
```
mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Remote Server (Different Server)

```bash
# .env
MONGODB_HOST=192.168.1.100          # Your MongoDB server IP
MONGODB_PORT=27017
MONGODB_USERNAME=rbdbuser
MONGODB_PASSWORD=adsijeoirFgfsd092rvcsxvsdewRS
MONGODB_DATABASE=w3kyc
MONGODB_REPLICA_SET=rs0
MONGODB_TLS_CA_FILE=./tls-certs/ca.crt
MONGODB_TLS_ALLOW_INVALID=true
```

**Result:**
```
mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@192.168.1.100:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Using Hostname

```bash
# .env
MONGODB_HOST=mongodb.example.com   # Your MongoDB hostname
MONGODB_PORT=27017
# ... rest of config
```

## Benefits

1. ✅ **Easy switching**: Change `MONGODB_HOST` to switch between local/remote
2. ✅ **No hardcoding**: Connection string built dynamically
3. ✅ **Environment-specific**: Different `.env` files for dev/staging/prod
4. ✅ **Type-safe**: Can add TypeScript types for validation
5. ✅ **Maintainable**: All connection components in one place

## Environment-Specific Configs

### Development (.env.development)
```bash
MONGODB_HOST=localhost
```

### Production (.env.production)
```bash
MONGODB_HOST=your-production-server.com
```

### Staging (.env.staging)
```bash
MONGODB_HOST=staging-mongodb.example.com
```

## Validation

Add validation to ensure required variables are set:

```javascript
function validateMongoConfig() {
  const required = ['MONGODB_USERNAME', 'MONGODB_PASSWORD'];
  const missing = required.filter(key => !process.env[key]);
  
  if (missing.length > 0) {
    throw new Error(`Missing required MongoDB config: ${missing.join(', ')}`);
  }
}

// Call before building URI
validateMongoConfig();
const MONGODB_URI = buildMongoURI();
```

## Summary

Instead of:
```bash
MONGODB_URI=mongodb://rbdbuser:password@localhost:27017/w3kyc?...
```

Use:
```bash
MONGODB_HOST=localhost
MONGODB_USERNAME=rbdbuser
MONGODB_PASSWORD=password
# ... etc
```

And build the URI in your application code. This gives you flexibility to easily switch between different MongoDB servers without changing your code.
