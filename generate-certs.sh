#!/usr/bin/env bash

mkdir certs private-ca-key

rm -f index.txt serial.txt
touch index.txt
echo '01' > serial.txt

# create the openssl certificate authority config file
cat > ca.cnf <<EOF
# OpenSSL CA configuration file
[ ca ]
default_ca = CA_default
[ CA_default ]
default_days = 365
database = index.txt
serial = serial.txt
default_md = sha256
copy_extensions = copy
unique_subject = no
# Used to create the CA certificate.
[ req ]
prompt=no
distinguished_name = distinguished_name
x509_extensions = extensions
[ distinguished_name ]
organizationName = Redpanda
commonName = Redpanda CA
[ extensions ]
keyUsage = critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign
basicConstraints = critical,CA:true,pathlen:1
# Common policy for nodes and users.
[ signing_policy ]
organizationName = supplied
commonName = optional
# Used to sign node certificates.
[ signing_node_req ]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth
# Used to sign client certificates.
[ signing_client_req ]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
EOF

openssl genrsa -out private-ca-key/ca.key 2048
chmod 400 private-ca-key/ca.key

openssl req \
-new \
-x509 \
-config ca.cnf \
-key private-ca-key/ca.key \
-days 365 \
-batch \
-out certs/ca.key

openssl req \
-new -x509 \
-config ca.cnf \
-key private-ca-key/ca.key \
-days 365 \
-batch \
-out certs/ca.crt

cat > node.cnf <<EOF
# OpenSSL node configuration file
[ req ]
prompt=no
distinguished_name = distinguished_name
req_extensions = extensions
[ distinguished_name ]
organizationName = Redpanda
[ extensions ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = localhost
DNS.2 = redpanda
DNS.3 = console
DNS.4 = connect
DNS.5 = "*.local"
DNS.6 = "*.redpanda.redpanda.svc.cluster.local"
IP.1 = 127.0.0.1
EOF

openssl genrsa -out certs/node.key 2048
chmod 400 certs/node.key

openssl req \
-new \
-config node.cnf \
-key certs/node.key \
-out node.csr \
-batch

openssl ca \
-config ca.cnf \
-keyfile private-ca-key/ca.key \
-cert certs/ca.crt \
-policy signing_policy \
-extensions signing_node_req \
-out certs/node.crt \
-outdir certs/ \
-in node.csr \
-batch

openssl x509 -in certs/node.crt -text | grep "X509v3 Subject Alternative Name" -A 1

rm ca.cnf index.txt index.txt.attr index.txt.old node.cnf node.csr serial.txt serial.txt.old

