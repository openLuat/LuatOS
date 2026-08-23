#!/usr/bin/env bash
# Generate self-signed CA + server + client + wrong-CA certs for LuatOS DTLS utest.
# Re-run safely: overwrites existing files in this directory.
#
# Git-Bash on Windows mangles /CN=... subjects into paths. Setting
# MSYS_NO_PATHCONV=1 below disables that for the openssl invocations.
set -euo pipefail

# Disable Git-Bash path mangling for all subsequent openssl calls.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

DAYS=1825
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

cat > _v3_server.ext <<'EOF'
authorityKeyIdentifier = keyid, issuer
basicConstraints       = CA:FALSE
keyUsage               = digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
subjectAltName         = IP:127.0.0.1, DNS:localhost
EOF

cat > _v3_client.ext <<'EOF'
authorityKeyIdentifier = keyid, issuer
basicConstraints       = CA:FALSE
keyUsage               = digitalSignature, keyEncipherment
extendedKeyUsage       = clientAuth
EOF

# 1) Root CA (trusted)
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout ca.key -out ca.crt -days "$DAYS" \
  -subj "/CN=LuatOS DTLS Test CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

# 2) Server cert signed by CA
openssl req -newkey rsa:2048 -nodes \
  -keyout server.key -out server.csr \
  -subj "/CN=127.0.0.1" 2>/dev/null
openssl x509 -req -in server.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days "$DAYS" -extfile _v3_server.ext 2>/dev/null

# 3) Client cert signed by CA (for mTLS)
openssl req -newkey rsa:2048 -nodes \
  -keyout client.key -out client.csr \
  -subj "/CN=LuatOS DTLS Test Client" 2>/dev/null
openssl x509 -req -in client.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out client.crt -days "$DAYS" -extfile _v3_client.ext 2>/dev/null

# 4) Independent (wrong) CA — used to sign a server cert that the LuatOS
#    client will reject because it does not chain to the trusted CA.
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout wrong_ca.key -out wrong_ca.crt -days "$DAYS" \
  -subj "/CN=LuatOS DTLS Test Wrong CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

# 5) Server cert signed by the wrong CA
openssl req -newkey rsa:2048 -nodes \
  -keyout wrong_server.key -out wrong_server.csr \
  -subj "/CN=127.0.0.1" 2>/dev/null
openssl x509 -req -in wrong_server.csr \
  -CA wrong_ca.crt -CAkey wrong_ca.key -CAcreateserial \
  -out wrong_server.crt -days "$DAYS" -extfile _v3_server.ext 2>/dev/null

# Cleanup intermediates
rm -f _v3_*.ext *.csr *.srl

echo "Generated:"
ls -1 ca.crt ca.key server.crt server.key client.crt client.key wrong_ca.crt wrong_ca.key wrong_server.crt wrong_server.key | sed 's/^/  /'
