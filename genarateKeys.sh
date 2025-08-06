#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
ASN=15169
BGPID="34.190.208.1"
KEY_DIR="/demo/bgpsec-keys"
VALIDITY_DAYS=365

# === PREPARE WORKING DIR ===
mkdir -p "$KEY_DIR"
cd "$KEY_DIR"

# Normalize ASN for CN
ASN_HEX=$(printf '%08X' "$ASN")

# Temp file names (using ASN prefix)
KEY_PEM="${ASN}.key.pem"
CERT_PEM="${ASN}.cert.pem"
CSR_FILE="${ASN}.csr"
CONF_FILE="bgpsec-openssl.conf"
CERT_DER="${ASN}.cert"
KEY_DER="${ASN}.der"

# === STEP 1: Generate EC Private Key ===
openssl ecparam -name prime256v1 -genkey -noout -out "$KEY_PEM"
chmod 600 "$KEY_PEM"

# === STEP 2: Create OpenSSL Config ===
cat > "$CONF_FILE" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = bgpsec_router_ext
prompt = no

[ req_distinguished_name ]
CN = ROUTER-${ASN_HEX}

[ bgpsec_router_ext ]
keyUsage = digitalSignature
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
extendedKeyUsage = 1.3.6.1.5.5.7.3.30
sbgp-autonomousSysNum = critical, AS:${ASN}, RDI:inherit
EOF

# === STEP 3: Generate CSR ===
openssl req -new -key "$KEY_PEM" -out "$CSR_FILE" -config "$CONF_FILE"

# === STEP 4: Generate Self-signed Cert ===
openssl req -x509 -days "$VALIDITY_DAYS" -key "$KEY_PEM" -in "$CSR_FILE" \
  -out "$CERT_PEM" -extensions bgpsec_router_ext -config "$CONF_FILE"

# === STEP 5: Convert cert/key to DER ===
openssl x509 -in "$CERT_PEM" -outform DER -out "$CERT_DER"
openssl ec -in "$KEY_PEM" -outform DER -out "$KEY_DER" || {
    echo "❌ ERROR: Failed to convert EC key to DER format."
    exit 1
}

# === STEP 6: Extract SKI from cert ===
SKI=$(openssl x509 -in "$CERT_PEM" -noout -text \
    | awk '/Subject Key Identifier/{getline; print}' \
    | tr -d ' \n:' | tr 'a-f' 'A-F')

if [[ -z "$SKI" || ${#SKI} -ne 40 ]]; then
    echo "❌ ERROR: Failed to extract valid SKI (got '$SKI')"
    rm -f "$KEY_PEM" "$CERT_PEM" "$CSR_FILE" "$CERT_DER" "$KEY_DER" "$CONF_FILE"
    exit 1
fi

# === STEP 7: Create final destination and move files ===
DIR1="${SKI:0:2}"
DIR2="${SKI:2:2}"
FINAL_DIR="${KEY_DIR}/${DIR1}/${DIR2}"
mkdir -p "$FINAL_DIR"

cp "$CERT_DER" "$FINAL_DIR/${SKI}.cert"
cp "$KEY_DER" "$FINAL_DIR/${SKI}.der"
cp "$KEY_PEM" "$FINAL_DIR/${SKI}.pem"

# === STEP 8: Create SKI lists ===
cat > "${KEY_DIR}/ski-list.txt" <<EOF
# BGPsec Public Key SKI mapping
${ASN}-SKI: ${SKI}
EOF

cat > "${KEY_DIR}/priv-ski-list.txt" <<EOF
# BGPsec Private Key SKI mapping
${ASN}-SKI: ${SKI}
EOF

# === CLEANUP ===
rm -f "$CERT_PEM" "$CSR_FILE" "$CERT_DER" "$KEY_DER" "$CONF_FILE" "$KEY_PEM"

echo "✅ Key and certificate generation complete."
echo "📁 Files stored under: $FINAL_DIR"
