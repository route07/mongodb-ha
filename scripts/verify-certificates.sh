#!/bin/bash
# Script to verify TLS certificates are consistent across nodes

echo "=========================================="
echo "Verifying TLS Certificate Consistency"
echo "=========================================="
echo ""

if [ ! -f "tls-certs/ca.crt" ]; then
    echo "⚠️  tls-certs/ca.crt not found"
    echo "   Run: ./scripts/generate-tls-certs.sh"
    exit 1
fi

echo "Checking certificates on THIS server..."
echo "-------------------------------------------"

echo "CA Certificate (ca.crt):"
md5sum tls-certs/ca.crt | awk '{print "  MD5: " $1}'

echo ""
echo "Server Certificate (server.pem):"
md5sum tls-certs/server.pem | awk '{print "  MD5: " $1}'

echo ""
echo "KeyFile (keyfile):"
md5sum tls-certs/keyfile | awk '{print "  MD5: " $1}'

echo ""
echo "Certificate Details:"
echo "-------------------------------------------"
if command -v openssl > /dev/null; then
    echo "CA Certificate Subject:"
    openssl x509 -in tls-certs/ca.crt -noout -subject 2>/dev/null | sed 's/^/  /'
    
    echo ""
    echo "Server Certificate Subject:"
    openssl x509 -in tls-certs/server.pem -noout -subject 2>/dev/null | sed 's/^/  /'
    
    echo ""
    echo "Server Certificate Issuer:"
    openssl x509 -in tls-certs/server.pem -noout -issuer 2>/dev/null | sed 's/^/  /'
    
    echo ""
    echo "Certificate Validity:"
    openssl x509 -in tls-certs/server.pem -noout -dates 2>/dev/null | sed 's/^/  /'
else
    echo "  (openssl not available - skipping certificate details)"
fi

echo ""
echo "=========================================="
echo "Instructions"
echo "=========================================="
echo ""
echo "To verify certificates match on other servers:"
echo ""
echo "1. Run this script on each server:"
echo "   ./scripts/verify-certificates.sh"
echo ""
echo "2. Compare MD5 hashes - they should be IDENTICAL"
echo ""
echo "3. If hashes don't match, copy certificates from primary:"
echo "   scp -r tls-certs/ user@other-server:~/ha-mongodb/tls-certs/"
echo ""
echo "4. Restart containers after copying:"
echo "   docker-compose restart"
echo ""
