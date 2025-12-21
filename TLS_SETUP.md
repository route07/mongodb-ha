# MongoDB TLS Configuration Guide

This guide explains how to enable and configure TLS (Transport Layer Security) for your MongoDB Docker instance.

## Overview

TLS encryption secures data in transit between MongoDB clients and the server. This setup uses self-signed certificates suitable for development/testing. For production environments, use certificates from a trusted Certificate Authority (CA).

## Quick Start

### 1. Generate TLS Certificates

Run the certificate generation script:

```bash
chmod +x generate-tls-certs.sh
./generate-tls-certs.sh
```

This will create a `tls-certs/` directory with:
- `ca.crt` - Certificate Authority certificate
- `server.crt` - MongoDB server certificate
- `server.key` - MongoDB server private key
- `client.crt` - Client certificate (for client authentication)
- `client.key` - Client private key
- `client.pem` - Combined client certificate and key

### 2. Start MongoDB with TLS

```bash
docker-compose up -d
```

MongoDB will now require TLS connections on port 27017.

## Configuration Details

### MongoDB TLS Settings

The MongoDB container is configured with:
- `--tlsMode requireTLS` - Requires TLS for all connections
- `--tlsCertificateKeyFile` - Server certificate and key
- `--tlsCAFile` - CA certificate for validating client certificates (optional)

### Connection String

When connecting to MongoDB with TLS enabled, use one of these connection strings:

**Using mongosh (MongoDB Shell):**
```bash
mongosh "mongodb://rbdbuser:rbdbpass1265asccZeaq@localhost:27017/?tls=true&tlsCAFile=./tls-certs/ca.crt"
```

**Using MongoDB drivers (Node.js example):**
```javascript
const { MongoClient } = require('mongodb');
const fs = require('fs');

const client = new MongoClient('mongodb://rbdbuser:rbdbpass1265asccZeaq@localhost:27017/', {
  tls: true,
  tlsCAFile: './tls-certs/ca.crt',
  // Optional: for client certificate authentication
  // tlsCertificateKeyFile: './tls-certs/client.pem',
});
```

**Using Python (pymongo):**
```python
from pymongo import MongoClient
import ssl

client = MongoClient(
    'mongodb://rbdbuser:rbdbpass1265asccZeaq@localhost:27017/',
    tls=True,
    tlsCAFile='./tls-certs/ca.crt',
    # Optional: for client certificate authentication
    # tlsCertificateKeyFile='./tls-certs/client.pem',
)
```

## TLS Modes

You can modify the TLS mode in `docker-compose.yaml`:

- `requireTLS` - All connections must use TLS (current setting)
- `preferTLS` - TLS is preferred but not required
- `allowTLS` - TLS is optional
- `disabled` - TLS is disabled

## Production Considerations

For production environments:

1. **Use CA-signed certificates**: Replace self-signed certificates with certificates from a trusted CA (e.g., Let's Encrypt, commercial CA)

2. **Client certificate authentication**: Enable mutual TLS by:
   - Uncommenting client certificate options in connection strings
   - Adding `--tlsAllowConnectionsWithoutCertificates false` to MongoDB command

3. **Certificate rotation**: Implement a process to rotate certificates before expiration

4. **Secure key storage**: Store private keys securely (use secrets management)

5. **Network security**: Consider removing port 27017 from public exposure and use internal networks only

## Troubleshooting

### Connection Refused
- Ensure certificates are generated and mounted correctly
- Check that MongoDB container is running: `docker-compose ps`
- Verify certificate permissions (should be 600 for keys, 644 for certs)

### Certificate Validation Errors
- Ensure you're using the correct CA certificate (`ca.crt`)
- Check that certificate Common Name (CN) matches the server hostname
- For self-signed certs, you may need to disable certificate validation in some clients (development only)

### mongo-express Connection Issues
- mongo-express may have limited TLS support
- Check container logs: `docker-compose logs mongo-express-survey`
- If TLS doesn't work with mongo-express, you may need to use `preferTLS` mode or connect directly via mongosh

## Testing TLS Connection

Test your TLS connection:

```bash
# Using mongosh
mongosh "mongodb://rbdbuser:rbdbpass1265asccZeaq@localhost:27017/?tls=true&tlsCAFile=./tls-certs/ca.crt"

# Check MongoDB logs
docker-compose logs mongo-survey
```

## Additional Resources

- [MongoDB TLS/SSL Configuration](https://www.mongodb.com/docs/manual/core/security-transport-encryption/)
- [MongoDB TLS/SSL Certificate Requirements](https://www.mongodb.com/docs/manual/core/security-transport-encryption/#certificate-requirements)
