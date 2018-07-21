#!/bin/sh
#
# Generates client config files for the server based on DNS zone
#
# Version: 1.0
# Date: 2018-07-21
#

DNS_DOMAIN=vpn.esolitos.com
DNS_ZONE_FILE=/etc/bind/master/$DNS_DOMAIN

OVPN_CONF_DIR=/etc/openvpn
OVPN_CLIENTS_DIR="$OVPN_CONF_DIR/clients.intranet"
OVPN_CLIENTS_IPP_FILE="$OVPN_CONF_DIR/ipp.intranet.txt"

OVPN_CLIENT_FILE_FORMAT='# IP auto-generated from DNS: %s\nifconfig-push %s 255.255.255.0\n'
OVPN_IPP_ROW_FORMAT='%s,%s\n'

# Truncate IPP file and clean existing config
if [ ! $DEBUG ]; then
   printf "Cleanup"
   echo '' >"$OVPN_CLIENTS_IPP_FILE"
   find $OVPN_CLIENTS_DIR -type f -name "*.$DNS_DOMAIN" -print -delete
fi

for client_dns_info in `grep -E 'IN\s+A' $DNS_ZONE_FILE |grep -vi 'ns' |awk '{ print $1 ":" $4 }'`; do
    client_hostname=`echo $client_dns_info |cut -d':' -f1`
    client_ipv4=`echo $client_dns_info |cut -d':' -f2`
    client_fqdn="${client_hostname}.${DNS_DOMAIN}"
    ovpn_client_config_file="$OVPN_CLIENTS_DIR/$client_fqdn"

    printf "\n# Processing client '%s' (%s)\n" "$client_hostname" "$client_ipv4"

    if [ $DEBUG ]; then
      printf "\nIPP Line:\n== START ==\n$OVPN_IPP_ROW_FORMAT\n==  END  ==\n" "$client_fqdn" "$client_ipv4"
	    printf "Client config: %s\n" "$ovpn_client_config_file"
	    printf "== START ==\n$OVPN_CLIENT_FILE_FORMAT\n==  END  ==\n" "$DNS_ZONE_FILE" "$client_ipv4"
    else
	    printf "$OVPN_IPP_ROW_FORMAT" "$client_fqdn" "$client_ipv4" >>"$OVPN_CLIENTS_IPP_FILE"
	    printf "$OVPN_CLIENT_FILE_FORMAT" "$DNS_ZONE_FILE" "$client_ipv4" >"$ovpn_client_config_file"
    fi
done
