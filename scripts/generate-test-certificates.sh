#!/usr/bin/env bash
# These certificates belong to an isolated localhost test server only.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="test/features/youtube/fixtures"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$fixture"
cat > "$scratch/root.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = ProxyYou Test Root
[extensions]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
CONFIG
cat > "$scratch/leaf.cnf" <<'CONFIG'
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost
CONFIG
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$scratch/ca.key" \
  -out "$fixture/ca.crt" -days 3650 -config "$scratch/root.cnf" 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -keyout "$fixture/localhost.key" \
  -out "$scratch/leaf.csr" -subj '/CN=localhost' 2>/dev/null
openssl x509 -req -in "$scratch/leaf.csr" -CA "$fixture/ca.crt" -CAkey "$scratch/ca.key" \
  -CAcreateserial -CAserial "$scratch/ca.srl" -out "$fixture/localhost.crt" -days 365 \
  -extfile "$scratch/leaf.cnf" 2>/dev/null
