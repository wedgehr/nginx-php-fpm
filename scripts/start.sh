#!/bin/bash

chmod 750 ./boot.sh && ./boot.sh

# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
