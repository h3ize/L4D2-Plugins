#!/bin/bash

SERVER_IP="YOURSERVERIP"
PORTS=(27015)

restart_server() {
    SERVER_NUMBER=$1
    /etc/init.d/srcds$SERVER_NUMBER restart
}

for i in "${!PORTS[@]}"; do
    PORT=${PORTS[$i]}
    SERVER_NUMBER=$((i + 1))

    nc -zv -w 120 $SERVER_IP $PORT &> /dev/null

    if [[ $? -ne 0 ]]; then
        restart_server $SERVER_NUMBER
    fi
done
