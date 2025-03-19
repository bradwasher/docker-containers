#!/bin/ash

# Exit on any error and pipefail to catch errors in pipelines
set -eo pipefail

# Define log file path
LOG_FILE="/var/log/docker_init.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a $LOG_FILE
}

# Check if running in privileged mode
if [ ! -w "/sys" ]; then
    log "[Error] Not running in privileged mode."
    exit 1
fi

# Check environment variables
if [ -z "${INTERFACE}" ]; then
    log "[Error] An interface must be specified."
    exit 1
fi

# Set default values for environment variables
: ${INTERFACE:=wlan1}
: ${IP_ADDR:=192.168.200.1}

: ${SUBNET:=192.168.200.0}
: ${SUBNET_CIDR:=/24}
: ${LEASE_START:=192.168.200.100}
: ${LEASE_END:=192.168.200.200}
: ${LEASE_LENGTH:=28800}

: ${PRI_DNS:=1.1.1.1}
: ${SEC_DNS:=8.8.8.8}

# Function to configure dhcp4
configure_dhcp() {
    cat > "/etc/kea-dhcp4.conf" <<EOF
{
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": [
        "${INTERFACE}"
      ]
    },
    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/tmp/dhcp4.leases"
    },
    "valid-lifetime": ${LEASE_LENGTH},
    "option-data": [
      {
        "name": "domain-name-servers",
        "data": "${PRI_DNS}, ${SEC_DNS}"
      }
    ],
    "subnet4": [
      {
	"id": 1,
        "subnet": "${SUBNET}${SUBNET_CIDR}",
        "pools": [
          {
            "pool": "${LEASE_START} - ${LEASE_END}"
          }
        ],
        "option-data": [
          {
            "name": "routers",
            "data": "${IP_ADDR}"
          }
        ]
      }
    ],
    "loggers": [
      {
        "name": "kea-dhcp4",
        "output_options": [
          {
            "output": "/tmp/kea-dhcp4.log",
            "maxver": 10
          }
        ],
        "severity": "INFO"
      }
    ]
  }
}

EOF
}



# Function to start DHCP server
start_dhcp() {
    log "Starting dhcp server..."
    
    kea-dhcp4 -c /etc/kea-dhcp4.conf &
}


# Function to cleanup on exit
cleanup() {
    log "Stopping dhcp server"
    killall kea-dhcp4
    log "Cleanup completed."

}


configure_dhcp
start_dhcp

# Cleanup when stopped
trap cleanup INT TERM
sleep infinity &
wait $!

