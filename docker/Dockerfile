FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        iproute2 iputils-ping dnsutils iperf3 \
        dnsmasq curl python3 rsync && \
    rm -rf /var/lib/apt/lists/*

# dnsmasq: forward .fips to FIPS daemon, everything else upstream
RUN printf '%s\n' \
    'port=53' \
    'listen-address=127.0.0.1' \
    'bind-interfaces' \
    'server=/fips/127.0.0.1#5354' \
    'no-resolv' \
    >> /etc/dnsmasq.conf

COPY fips fipsctl fipstop /usr/local/bin/
RUN chmod +x /usr/local/bin/fips /usr/local/bin/fipsctl /usr/local/bin/fipstop

RUN printf 'Fuck IPs!\n' > /root/index.html

EXPOSE 2121/udp
EXPOSE 443/tcp

ENTRYPOINT ["/bin/bash", "-c", "dnsmasq && iperf3 -s -D && python3 -m http.server 8000 -d /root -b :: &>/dev/null & exec fips --config /etc/fips/fips.yaml"]