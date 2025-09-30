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
if [ -z "${GATEWAY_INTERFACE}" ]; then
    log "[Error] An interface must be specified."
    exit 1
fi

# Set default values for environment variables
: ${IP_ADDRESS:=192.168.200.1}
: ${GATEWAY_INTERFACE:=wlan1}
: ${GATEWAY_NAME:=my site}
: ${GATEWAY_PORT:=2050}
: ${NETWORK:=192.168.200.0}
: ${NETWORK_CIDR:=/24}
: ${STATUS_PAGE:=status.html}
: ${SPLASH_PAGE:=splash.html}
: ${REDIRECT_URL:=none}
: ${MAX_CLIENTS:=250}
: ${AUTH_IDLE_TIMEOUT:=480}
: ${DEBUG_LEVEL:=3}
: ${BIN_AUTH:=}


configure_nodogsplash() {
    cat > "/etc/nodogsplash/nodogsplash.conf" <<EOF
GatewayInterface ${GATEWAY_INTERFACE}
GatewayName ${GATEWAY_NAME}
GatewayAddress ${IP_ADDRESS}
GatewayPort ${GATEWAY_PORT}
GatewayIPRange ${NETWORK}${NETWORK_CIDR}

StatusPage ${STATUS_PAGE}
SplashPage ${SPLASH_PAGE}
RedirectURL ${REDIRECT_URL}

MaxClients ${MAX_CLIENTS}
AuthIdleTimeout ${AUTH_IDLE_TIMEOUT}

# Firewall Rules
FirewallRuleSet authenticated-users {
    FirewallRule allow all
}

FirewallRuleSet preauthenticated-users {
    FirewallRule allow tcp port 53
    FirewallRule allow udp port 53
}

FirewallRuleSet users-to-router {
    FirewallRule allow udp port 53
    FirewallRule allow tcp port 53
    FirewallRule allow udp port 67
    FirewallRule allow tcp port 22
    FirewallRule allow tcp port 80
    FirewallRule allow tcp port 443
}

DebugLevel ${DEBUG_LEVEL}

EOF

# check if BinAuth is set, if so then append to config
if [[ ! -z "${BIN_AUTH}" ]]; then
    echo "BinAuth ${BIN_AUTH}" >> /etc/nodogsplash/nodogsplash.conf 
fi
 
}

# Function to start hostapd
start_nodogsplash() {
    log "Starting nodogsplash..."
    /usr/bin/nodogsplash - c /etc/nodogsplash/nodogsplash.conf &
}

# Clean up and stop nodogsplash
cleanup() {
    log "Stopping nodogsplash"
    killall nodogsplash
    killall sleep

    log "Clearing all iptables rules"
    iptables -t nat -X ndsOUT 2>/dev/null
    iptables -X ndsAUT 2>/dev/null
    iptables -X ndsNET 2>/dev/null
    iptables -D INPUT -i ${GATEWAY_INTERFACE} -s ${NETWORK}${NETWORK_CIDR} -d 0.0.0.0/0 -j ndsRTR 2>/dev/null
    iptables -D FORWARD -i ${GATEWAY_INTERFACE} -s ${NETWORK}${NETWORK_CIDR} -d 0.0.0.0/0 -j ndsNET 2>/dev/null


    log "Cleanup complete"
}


configure_nodogsplash
start_nodogsplash


# Cleanup when stopped
trap cleanup INT TERM
sleep infinity &
wait $!




