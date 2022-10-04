#!/usr/bin/with-contenv bashio

#bashio::log.level "debug"

source dns_dynu.sh


CERT_DIR=/data/letsencrypt
WORK_DIR=/data/workdir

# Let's encrypt
LE_UPDATE="0"

# DynuDNS
if bashio::config.has_value "ipv4"; then IPV4=$(bashio::config 'ipv4'); else IPV4="https://ipv4.text.wtfismyip.com"; fi
if bashio::config.has_value "ipv6"; then IPV6=$(bashio::config 'ipv6'); else IPV6="https://ipv6.text.wtfismyip.com"; fi
TOKEN=$(bashio::config 'token')
DOMAINS=$(bashio::config 'domains')
WAIT_TIME=$(bashio::config 'seconds')

export Dynu_Token=$TOKEN 
bashio::log.debug "Token:" "$Dynu_Token"

# Function that performe a renew
function le_renew() {
    local domain_args=()
    local aliases=''

    # Prepare domain for Let's Encrypt
    for domain in ${DOMAINS}; do
        for alias in $(jq --raw-output --exit-status "[.aliases[]|{(.alias):.domain}]|add.\"${domain}\" | select(. != null)" /data/options.json) ; do
            aliases="${aliases} ${alias}"
        done
    done

    aliases="$(echo "${aliases}" | tr ' ' '\n' | sort | uniq)"

    bashio::log.info "Renew certificate for domains: $(echo -n "${DOMAINS}") and aliases: $(echo -n "${aliases}")"

    for domain in $(echo "${DOMAINS}" "${aliases}" | tr ' ' '\n' | sort | uniq); do
        domain_args+=("--domain" "${domain}")
    done

    dehydrated --cron --hook ./hooks.sh --challenge dns-01 "${domain_args[@]}" --out "${CERT_DIR}" --config "${WORK_DIR}/config" || true
    LE_UPDATE="$(date +%s)"
}   

# Register/generate certificate if terms accepted
if bashio::config.true 'lets_encrypt.accept_terms'; then
    # Init folder structs
    mkdir -p "${CERT_DIR}"
    mkdir -p "${WORK_DIR}"

    # Clean up possible stale lock file
    if [ -e "${WORK_DIR}/lock" ]; then
        rm -f "${WORK_DIR}/lock"
        bashio::log.warning "Reset dehydrated lock file"
    fi

    # Generate new certs
    if [ ! -d "${CERT_DIR}/live" ]; then
        # Create empty dehydrated config file so that this dir will be used for storage
        touch "${WORK_DIR}/config"

        dehydrated --register --accept-terms --config "${WORK_DIR}/config"
    fi
fi

# Run dynu
while true; do

    [[ ${IPV4} != *:/* ]] && ipv4=${IPV4} || ipv4=$(curl -s -f -m 10 "${IPV4}") || true 
    [[ ${IPV6} != *:/* ]] && ipv6=${IPV6} || ipv6=$(curl -s -f -m 10 "${IPV6}") || true 

    bashio::log.debug "ipv4:" "$ipv4"
    bashio::log.debug "ipv6:" "$ipv6"

    for domain in ${DOMAINS}; do
        _get_domain_id "${domain}"
        bashio::log.debug "DynuDnsId:" "${DynuDnsId}"
        answer=$(curl -s -X POST -H "API-Key: $TOKEN" -H "Content-Type: application/json" "https://api.dynu.com/v2/dns/$DynuDnsId" -d "{\"name\":\"$domain\",\"ipv4Address\": \"${ipv4}\",\"ipv6Address\": \"${ipv6}\"}")
        bashio::log.debug "${answer}"
    done
    
    now="$(date +%s)"
    if bashio::config.true 'lets_encrypt.accept_terms' && [ $((now - LE_UPDATE)) -ge 43200 ]; then
        le_renew
    fi
    
    sleep "${WAIT_TIME}"
done
