#!/bin/bash
# Container entrypoint for a standalone FIPS node.
set -e

# Start dnsmasq for .fips DNS resolution
dnsmasq

exec fips --config /etc/fips/fips.yaml