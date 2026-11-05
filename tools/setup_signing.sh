#!/bin/zsh
# Creates a local self-signed code-signing identity "WindowSwitcher Local Signing" (one time).
# A stable identity keeps macOS privacy permissions (Accessibility, Screen Recording) across rebuilds.
set -euo pipefail
NAME="WindowSwitcher Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then echo "Identity already exists"; exit 0; fi
T=$(mktemp -d)
cat > $T/c.cnf <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout $T/k.pem -out $T/c.pem -days 3650 -config $T/c.cnf 2>/dev/null
openssl pkcs12 -export -inkey $T/k.pem -in $T/c.pem -out $T/c.p12 -passout pass:tmp -legacy 2>/dev/null || \
openssl pkcs12 -export -inkey $T/k.pem -in $T/c.pem -out $T/c.p12 -passout pass:tmp
security import $T/c.p12 -k ~/Library/Keychains/login.keychain-db -P tmp -T /usr/bin/codesign
rm -rf $T
echo "Created identity"
