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
: ${AP_ADDR:=192.168.200.1}
: ${OUTBOUND_INTERFACE:=eth0}
: ${SSID:=Orion}
: ${CHANNEL:=11}
: ${DRIVER:=nl80211}
: ${LOGGER_SYSLOG:=127}
: ${LOGGER_SYSLOG_LEVEL:=2}
: ${LOGGER_STDOUT:=127}
: ${LOGGER_STDOUT_LEVEL:=2}
: ${COUNTRY_CODE:=US}
: ${IEEE80211D:=1}
: ${IEEE80211H:=1}
: ${HW_MODE:=g}
: ${BEACON_INT:=100}

: ${CTRL_INTERFACE:=/var/run/hostapd}

: ${SUBNET:=192.168.200.0}
: ${SUBNET_CIDR:=/24}
: ${SUBNET_MASQ:=255.255.255.0}

: ${MACADDR_ACL:=0}
: ${AUTH_ALGS:=1}
: ${IGNORE_BROADCAST_SSID:=0}
: ${WPA:=2}
: ${WPA_PASSPHRASE:=password}
: ${WPA_KEY_MGMT:=WPA-PSK}
: ${WPA_PAIRWISE:=TKIP}
: ${RSN_PAIRWISE:=CCMP}

bssid=$(ip link show $AP_INTERFACE | awk '/link/ {print $2}')
: ${BSSID:=$bssid}
echo AP BSSID ${BSSID}


configure_hostapd() {
    if [ ! -f "/etc/hostapd.conf" ]; then
        cat > "/etc/hostapd.conf" <<EOF
driver=${DRIVER}

logger_syslog=${LOGGER_SYSLOG}
logger_syslog_level=${LOGGER_SYSLOG_LEVEL}
logger_stdout=${LOGGER_STDOUT}
logger_stdout_level=${LOGGER_STDOUT_LEVEL}

country_code=${COUNTRY_CODE}

ieee80211d=${IEEE80211D}
ieee80211h=${IEEE80211H}

hw_mode=${HW_MODE}
beacon_int=${BEACON_INT}
channel=${CHANNEL}
interface=${AP_INTERFACE}

ssid=${SSID}
bssid=${BSSID}

ctrl_interface=${CTRL_INTERFACE}

macaddr_acl=${MACADDR_ACL}

ignore_broadcast_ssid=${IGNORE_BROADCAST_SSID}

EOF
    fi

    # specify encryption
    # WPA 2 or 3 encryption
    if [ ${WPA} != "0" ]; then
        cat >> "/etc/hostapd.conf" <<EOF
wpa=${WPA}
wpa_passphrase=${WPA_PASSPHRASE}
wpa_key_mgmt=${WPA_KEY_MGMT}
wpa_pairwise=${WPA_PAIRWISE}
rsn_pairwise=${RSN_PAIRWISE}
auth_algs=${AUTH_ALGS}
EOF
    fi

}


# Function to setup iptables
setup_iptables() {
    log "Setting iptables for outgoing traffics on ${OUTBOUND_INTERFACE}..."
    
    # clear any old rules
    iptables -t nat -D POSTROUTING -j HOSTAPD || :
    iptables -t nat -F HOSTAPD || :
    iptables -t nat -X HOSTAPD || :

    iptables -D FORWARD -j HOSTAPD || :
    iptables -F HOSTAPD || :
    iptables -X HOSTAPD || :

    # create natting hostapd chain
    iptables -t nat -N HOSTAPD
    iptables -t nat -A POSTROUTING -j HOSTAPD
    iptables -t nat -A HOSTAPD -s ${SUBNET}${SUBNET_CIDR} -o ${OUTBOUND_INTERFACE} -j MASQUERADE

    # create forwarding hostapd chain
    iptables -N HOSTAPD
    iptables -A FORWARD -j HOSTAPD
    iptables -A HOSTAPD -i ${OUTBOUND_INTERFACE} -o ${AP_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A HOSTAPD -i ${AP_INTERFACE} -o ${OUTBOUND_INTERFACE} -j ACCEPT
}


# Function to setup AP interface
setup_interface() {
    ip link set ${AP_INTERFACE} up
    ip addr flush dev ${AP_INTERFACE}
    ip addr add ${AP_ADDR}${SUBNET_CIDR} dev ${AP_INTERFACE}
    iw reg set ${COUNTRY_CODE}
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

# Function to cleanup on exit
cleanup() {
    log "Removing iptables rules..."
    iptables -t nat -D POSTROUTING -j HOSTAPD || :
    iptables -t nat -F HOSTAPD || :
    iptables -t nat -X HOSTAPD || :

    iptables -D FORWARD -j HOSTAPD || :
    iptables -F HOSTAPD || :
    iptables -X HOSTAPD || :

    log "Stopping dhcp server"
    killall hostapd
    killall sleep
    log "Cleanup completed."

}


# Function to start hostapd
start_hostapd() {
    log "Starting hostapd..."
    /usr/sbin/hostapd /etc/hostapd.conf &
}


setup_interface
setup_nat
setup_iptables
configure_hostapd
start_hostapd


# Cleanup when stopped
trap cleanup INT TERM
sleep infinity &
wait $!
