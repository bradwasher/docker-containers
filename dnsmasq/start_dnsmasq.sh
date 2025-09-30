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
if [ -z "${AP_INTERFACE}" ]; then
    log "[Error] An interface must be specified."
    exit 1
fi

# Set default values for environment variables
: ${AP_INTERFACE:=wlan1}
: ${OUTBOUND_INTERFACE:=eth0}
: ${SUBNET:=192.168.200.0}
: ${SUBNET_CIDR:=/24}
: ${SUBNET_MASQ:=255.255.255.0}
: ${LEASE_START:=192.168.200.100}
: ${LEASE_END:=192.168.200.200}
: ${LEASE_LENGTH:=24h}
: ${AP_ADDR:=192.168.200.1}
: ${PRI_DNS:=1.1.1.1}
: ${SEC_DNS:=8.8.8.8}
: ${SSID:=Test}
: ${COUNTRY_CODE:=US}


# Function to setup AP interface
setup_interface() {
    ip link set ${AP_INTERFACE} up
    ip addr flush dev ${AP_INTERFACE}
    ip addr add ${AP_ADDR}/24 dev ${AP_INTERFACE}
    iw reg set ${COUNTRY_CODE}
    cat /proc/sys/net/ipv4/ip_dynaddr
    cat /proc/sys/net/ipv4/ip_forward
}

# Function to setup NAT settings
setup_nat() {
    log "Configuring NAT settings ip_dynaddr, ip_forward"
    for i in ip_dynaddr ip_forward; do
        if [ $(cat /proc/sys/net/ipv4/$i) -eq 1 ]; then
            log "$i already 1"
        else
            echo "1" > /proc/sys/net/ipv4/$i
            log "$i set to 1"
        fi
    done
}

# Function to setup iptables
setup_iptables() {
    log "Setting iptables for outgoing traffics on ${OUTBOUND_INTERFACE}..."
    iptables -t nat -D POSTROUTING -s ${SUBNET}${SUBNET_CIDR} -o ${OUTBOUND_INTERFACE} -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s ${SUBNET}${SUBNET_CIDR} -o ${OUTBOUND_INTERFACE} -j MASQUERADE

    iptables -D FORWARD -i ${OUTBOUND_INTERFACE} -o ${AP_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -i ${OUTBOUND_INTERFACE} -o ${AP_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

    iptables -D FORWARD -i ${AP_INTERFACE} -o ${OUTBOUND_INTERFACE} -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -i ${AP_INTERFACE} -o ${OUTBOUND_INTERFACE} -j ACCEPT
}

# Function to configure DNSMASQ
configure_dnsmasq() {
    cat > "/etc/dnsmasq.conf" <<EOF
#domain-needed
bogus-priv
#filterwin2k
no-resolv
no-poll
#port=0
server=${PRI_DNS}
server=${SEC_DNS}
#local=/net.local/
#listen-address=${AP_ADDR}
#interface=${AP_INTERFACE}
#expand-hosts
no-hosts
#domain=mydomain.org

dhcp-range=${LEASE_START},${LEASE_END},${LEASE_LENGTH}
dhcp-option=option:router,${AP_ADDR}
#dhcp-option=3,${AP_ADDR}
dhcp-authoritative
dhcp-leasefile=/var/lib/dnsmasq/dnsmasq.leases

EOF
}



# Function to start DHCP server
start_dnsmasq() {
    log "Starting dnsmasq server..."
    dnsmasq &
}


# Function to cleanup on exit
cleanup() {
    log "Removing iptables rules..."
    iptables -t nat -D POSTROUTING -s ${SUBNET}${SUBNET_CIDR} -o ${OUTBOUND_INTERFACE} -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i ${OUTBOUND_INTERFACE} -o ${AP_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i ${AP_INTERFACE} -o ${OUTBOUND_INTERFACE} -j ACCEPT 2>/dev/null || true
    
    log "Stopping DNSMASQ"
    killall dnsmasq
    
    log "Cleanup completed."

}


setup_interface
setup_nat
setup_iptables
configure_dnsmasq
start_dnsmasq

# Cleanup when stopped
trap cleanup INT TERM
sleep infinity &
wait $!
