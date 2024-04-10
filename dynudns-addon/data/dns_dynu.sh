#!/usr/bin/with-contenv bashio

## CONSTANTS
declare DNS_API_TOKEN
DNS_API_ENDPOINT='https://api.dynu.com/v2'


## VARIABLES
declare current_domain_config
declare domain_id

########  Public functions #####################
function dns_dynu_update_ipv4_ipv6() {
    local domain="$1"
    local current_ipv4_address="$2"
    local current_ipv6_address="$3"

    if ! _get_domain_config "$domain"; then
      bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "DynuDNS _get_domain_config API call failed."
      return 1
    fi

    dns_configured_ipv4_address=$(echo "$current_domain_config" | jq -r '.ipv4Address')
    dns_configured_ipv6_address=$(echo "$current_domain_config" | jq -r '.ipv6Address')
    statusCode=$(echo "$current_domain_config" | jq '.statusCode')

    # Create new domain configuration and replace IPv4 and IPv6 addresses
    new_domain_config=$current_domain_config

    if  [[ "$current_ipv4_address" == *.* ]]; then # Replace ipv4Address and ipv4 fields
        new_domain_config=$(echo "$new_domain_config" | jq ".ipv4Address = \"$current_ipv4_address\" | .ipv4 = true")
    fi
    if  [[ "$current_ipv6_address" == *:* ]]; then # Replace ipv6Address and ipv6 fields
        new_domain_config=$(echo "$new_domain_config" | jq ".ipv6Address = \"$current_ipv6_address\" | .ipv6 = true")
    fi

    # Update Domain config if it's different
    bashio::log.info "Updating Dynu DNS: $domain IP addresses"
    if [[ "$dns_configured_ipv4_address" != "$current_ipv4_address" ]] || [[ "$dns_configured_ipv6_address" != "$current_ipv6_address" ]] ; then

      # Set the new domain configuration with updated IP addresses.
      if ! _set_domain_config "$domain" "$new_domain_config"; then
        bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "DynuDNS _set_domain_config API call failed."
        return 1
      else
        bashio::log.info "[${FUNCNAME[0]} completed successfully!"
        return 0
      fi
    fi
}

#Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dynu_add_txt_record() {
  local fulldomain="$1"
  local txtvalue="$2"

  if [ -z "$DNS_API_TOKEN" ]; then
    bashio::log.warn "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Missing Dynu DNS_API_TOKEN."
    return 1
  fi

  bashio::log.debug "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Get domain ID"
  if ! _get_domain_id "$fulldomain"; then
    bashio::log.warn "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Invalid domain."
    return 1
  fi

  bashio::log.debug "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Creating TXT record."
  if ! _dynu_rest POST "dns/$domain_id/record" "{\"domainId\":\"$domain_id\",\"nodeName\":\"_acme-challenge\",\"recordType\":\"TXT\",\"textData\":\"$txtvalue\",\"state\":true,\"ttl\":90}"; then
    bashio::log.warn "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Dynu Rest API call failed."
    return 1
  fi

  if ! _contains "$response" "200"; then
    bashio::log.warn "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Could not add TXT record."
    return 1
  fi

  return 0
}

#Usage: rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dynu_rm_record() {
  local fulldomain="$1"
  local txtvalue="$2"

  if [ -z "$DNS_API_TOKEN" ]; then
    bashio::log.error "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Missing Dynu DNS_API_TOKEN."
    return 1
  fi

  bashio::log.info "Get domain ID"
  if ! _get_domain_id "$fulldomain"; then
    bashio::log.error "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Invalid domain."
    return 1
  fi

  bashio::log.info "Checking for TXT record."
  if ! _get_record_id "$fulldomain" "$txtvalue"; then
    bashio::log.error "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Could not get TXT record id."
    return 1
  fi

  if [ "$_dns_record_id" = "" ]; then
    bashio::log.error "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "TXT record not found."
    return 1
  fi

  bashio::log.info "Removing TXT record."
  if ! _delete_record "$domain_id" "$_dns_record_id"; then
    bashio::log.error "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Could not remove TXT record $_dns_record_id."
  fi

  return 0
}

_get_domain_id() {
  local domain="$1"

  # Perform server request
  bashio::log.debug "${FUNCNAME[0]} $@ Getting DynuDNS ID for $domain"
  if ! _dynu_rest GET "dns" ""; then
    bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "DynuDNS GET dns API call failed."
    return 1
  else
    bashio::log.trace "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "RESPONSE FOLLOWS \nresponse='$(echo $response)' \n"
  fi

  # Check if response has JSON domains array and grab it
  if ! domains=$(echo "$response" | jq -e '.domains'); then
    bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "response does not have JSON domains array."
    return 1
  else
    bashio::log.trace "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "DOMAINS FOLLOWS \ndomains='$(echo $domains | jq)' \n"
  fi

  # Check if domains has the domain of interest and grab it
  if ! domain_config=$(echo "$domains" | jq -e --arg name "$domain" '.[] | select(.name == $name)' ); then
    bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "domains does not have domain_config for $domain."
    return 1
  else
    bashio::log.trace "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "DOMAIN CONFIG FOLLOWS \ndomain_config='$(echo $domain_config)' \n"
  fi 

  # Check if domain_config has the numeric ID of interest and grab it
  if ! domain_id_parsed=$(echo "$domain_config" | jq -e '.id'); then
    bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "domain_config does not have domain_id."
    return 1
  else
    bashio::log.trace "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "DOMAIN ID FOLLOWS \ndomain_id='$(echo $domain_id_parsed)' \n"
  fi 

  # Check if domain_id_parsed is non-empty and is a number greater than 100 and grab it.
  if [[ -n "$domain_id_parsed" ]] && [[ "$domain_id_parsed" =~ ^[0-9]+$ ]] && [[ 100 -le $domain_id_parsed ]]; then
    domain_id=$domain_id_parsed
    bashio::log.debug "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Successfully fetched domain_id: $domain_id"
    return 0
  else
    bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "Failed to parse domain_id: $domain_id out of JSON response."
    return 1
  fi

  bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "Failed to get DynuDNS domain id, unknown error. Exiting."
  return 1

}

function _get_domain_config(){
    local domain="$1"

    # Get domain numeric id
    if _get_domain_id "${domain}"; then
        bashio::log.debug "domain_id: ${domain_id}"
    else
        bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "Failed to get domain_id for $domain."
        return 1
    fi 
        
    # Get current domain configuration
    bashio::log.info "Getting current domain configuration for domain: ${domain}"
    if current_domain_config="$(curl -s -f -H "API-Key: $DNS_API_TOKEN" -H "Content-Type: application/json" "https://api.dynu.com/v2/dns/$domain_id")"; then
        bashio::log.debug "domain_id: ${domain_id}" "$LINENO" "${BASH_SOURCE[0]}"
    else
        bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "Failed to get request domain configuration for $domain."
        return 1
    fi 

    # Check domain request status code
    statusCode=$(echo "$current_domain_config" | jq '.statusCode')
    if  [ "$statusCode" -eq 200 ]; then
        bashio::log.debug "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Dynu DNS get config Success. \"statusCode\": $statusCode"
    else
        bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Dynu DNS get config failed, not \"statusCode:\" ${statusCode}. It answered: ${answer}"
        return 1
    fi

}

function _set_domain_config(){
    local domain="$1"
    local new_domain_config="$2"

    # Get domain numeric id
    if _get_domain_id "${domain}"; then
        bashio::log.trace "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "domain_id: $domain_id"
    else
        bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "Failed to get domain_id for $domain. Skipping."
        return 1
    fi 
        
    # Update Domain config
    bashio::log.info "Updating Dynu DNS: ${domain} Domain Configuration"

    answer="$(curl -s -f -X POST -H "API-Key: $DNS_API_TOKEN" -H "Content-Type: application/json" "https://api.dynu.com/v2/dns/$domain_id" -d "$new_domain_config")"
    statusCode=$(echo "$answer" | jq '.statusCode')

    if [ "$statusCode" -eq 200 ]; then
        bashio::log.info "Dynu DNS IP update Success. "statusCode:" $statusCode"
        return 0
    else
        bashio::log.warning "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}]" "Dynu DNS IP update did not succeed. "statusCode:" "$statusCode" . It answered: $answer"
        return 1
    fi

}

_get_record_id() {
  local fulldomain="$1"
  local txtvalue="$2"

  if ! _dynu_rest GET "dns/$domain_id/record" ""; then
    return 1
  fi

  if ! _contains "$response" "$txtvalue"; then
    _dns_record_id=0
    return 0
  fi

  _dns_record_id=$(printf "%s" "$response" | sed -e 's/[^{]*\({[^}]*}\)[^{]*/\1\n/g' | grep "\"textData\":\"$txtvalue\"" | sed -e 's/.*"id":\([^,]*\).*/\1/')
  bashio::log.debug "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "DynuDNS _dns_record_id id is: ${_dns_record_id}"

  return 0
}

_delete_record() {
  local domain_id="$1"
  local dns_record_id="$2"

  if ! _dynu_rest DELETE "dns/$domain_id/record/$dns_record_id" ""; then
    return 1
  fi

  if ! _contains "$response" "200"; then
    return 1
  fi

  return 0
}

_dynu_rest() {
  m="$1"
  ep="$2"
  data="$3"

  _H1="API-Key: $DNS_API_TOKEN"
  _H2="Content-Type: application/json"

  bashio::log.debug "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "Performing REST API method: $m to endpoint: $DNS_API_ENDPOINT/$ep"
  if [ "$data" ]; then
    response=$(curl -s -H "$_H1" -H "$_H2" -X $m "$DNS_API_ENDPOINT/$ep" -d $data) # outgoing
  else
    response=$(curl -s -H "$_H1" -H "$_H2" -X $m "$DNS_API_ENDPOINT/$ep") # incoming
  fi

  local ret=$?
  if [ "$ret" != "0" ]; then
    bashio::log.warn "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "return code is: $ret"
    return 1
  fi
  bashio::log.trace "[${FUNCNAME[0]} ${BASH_SOURCE[0]}:${LINENO}] Args: $@" "\nresponse='$(echo $response)' \n"

  return 0
}

_contains() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "$_sub" >/dev/null 2>&1
}
