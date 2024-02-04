#!/usr/bin/with-contenv bashio

# # Have BASH tell you which function it errored on, rather than exit silently.
# function error_handler {
#     local exit_code=$?
#     local cmd="${BASH_COMMAND}" # Command that triggered the ERR
#     echo "Error in script at: '${cmd}' with exit code: ${exit_code}"
#     # Simple backtrace
#     local frame=0
#     while caller $frame; do
#         ((frame++));
#     done
# }

# trap 'error_handler' ERR

bashio::log.level "info"

source dns_dynu.sh
source le.sh
source ddns.sh

CONFIG_PATH=/data/options.json

function update_dns_ip_addresses(){

    declare current_ipv4_address
    if ! hassio_determine_ipv4_address; then
        bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Could not determine IPv4 address"
    fi

    declare current_ipv6_address
    if ! hassio_determine_ipv6_address; then
        bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Could not determine IPv6 address"
    fi

    # Update each domain
    for domain in ${DOMAINS}; do
        if ! dns_dynu_update_ipv4_ipv6 "$domain" "$current_ipv4_address" "$current_ipv6_address"; then
            bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Could not update Dynu DNS IP address records for domain: $domain"
            continue
        fi
    done

    return 0

}

## INIT
bashio::log.info "[dynudns- Add On] Initializing Dynu DNS Home Assistant Add-On"

# get config variables from hassio
if ! hassio_get_config_variables; then
        bashio::log.error "[DynuDNS Add-On ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Failed to get config arguments from Add On Config"
        exit 1
fi

# initialize lets encrypt
if ! le_init $LE_TERMS_ACCEPTED; then
        bashio::log.error "[DynuDNS Add-On ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Lets Encrypt Init failed."
        exit 1
fi

bashio::log.info "[DynuDNS Add-On]" "Entering main Dynu DNS and Let's Encrypt Renew loop"
while true; do

    # update IP Addresses
    if ! update_dns_ip_addresses; then
        bashio::log.warning "[DynuDNS Add-On ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Could not update Dynu DNS IP address"
    fi

    # update certificates
    if ! le_renew $LE_TERMS_ACCEPTED "$DOMAINS" "$ALIASES"; then
        bashio::log.warning "[DynuDNS Add-On ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "lets encrypt renew failed."
    fi

    sleep "${IP_UPDATE_WAIT_SECONDS}"
done
