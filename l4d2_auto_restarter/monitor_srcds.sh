#!/bin/bash

SRCDS_DIR="/etc/init.d" // Change this to whatever directory your SRCDS files are in.

is_running() {
    local service=$1
    if screen -list | grep -q "$service"; then
        return 0
    else
        return 1
    fi
}

start_srcds() {
    local service=$1
    echo "Starting $service..."
    sudo $SRCDS_DIR/$service start
}

while true; do
    for srcds_script in $SRCDS_DIR/srcds*; do
        service_name=$(basename $srcds_script)
        if ! is_running $service_name; then
            start_srcds $service_name
        fi
    done
    sleep 15
done
