#! /bin/sh

mkdir -p "$(pwd)/test/certs/testca"
mkdir -p "$(pwd)/test/certs/client"
mkdir -p "$(pwd)/test/certs/server"

openssl req -nodes -x509 -newkey rsa:2048 -keyout "$(pwd)/test/certs/testca/cacert.key" -out "$(pwd)/test/certs/testca/cacert.pem" \
    -subj "/C=HU/L=Stockholm/O=hazardfn/CN=$(hostname -f)"

openssl req -nodes -newkey rsa:2048 -keyout "$(pwd)/test/certs/server/server.pkcs8" -out "$(pwd)/test/certs/server/server.csr" \
    -subj "/C=HU/L=Stockholm/O=hazardfn/CN=$(hostname -f)"

openssl x509 -req -in "$(pwd)/test/certs/server/server.csr" -CA "$(pwd)/test/certs/testca/cacert.pem" -CAkey "$(pwd)/test/certs/testca/cacert.key" \
    -CAcreateserial -out "$(pwd)/test/certs/server/server.crt"

openssl req -nodes -newkey rsa:2048 -keyout "$(pwd)/test/certs/client/client.key" -out "$(pwd)/test/certs/client/client.csr" \
    -subj "/C=HU/L=Stockholm/O=hazardfn/CN=$(hostname -f)"

openssl x509 -req -in "$(pwd)/test/certs/client/client.csr" -CA "$(pwd)/test/certs/testca/cacert.pem" -CAkey "$(pwd)/test/certs/testca/cacert.key" \
    -out "$(pwd)/test/certs/client/client.crt"
