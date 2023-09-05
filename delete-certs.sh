#!/bin/sh
chmod 644 certs/node.key private-ca-key/ca.key 2> /dev/null
rm -r certs private-ca-key 2> /dev/null 2> /dev/null

