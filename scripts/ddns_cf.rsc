# Cloudflare Dynamic DNS update script
# Required policy: read, write, test, policy
# Add this script to scheduler
# Install DigiCert root CA or disable check-certificate
# Configuration ---------------------------------------------------------------------

:local TOKEN ""
:local ZONEID ""
:local RECORDID ""
:local RECORDNAME ""
:local WANIF ""

#------------------------------------------------------------------------------------

:global IP4NEW
:global IP4CUR

:local url "https://api.cloudflare.com/client/v4/zones/$ZONEID/dns_records/$RECORDID/"

:if ([/interface get $WANIF value-name=running]) do={
# Get the current public IP
    :local currentIP [/ip address get [/ip address find interface=$WANIF ] address];
    :set IP4NEW [:pick $currentIP 0 [:find $currentIP "/"]];
# Check if IP has changed
    :if ($IP4NEW != $IP4CUR) do={
        :log info "CF-DDNS: Public IP changed to $IP4NEW, updating"
        :local cfapi [/tool fetch http-method=put mode=https url=$url check-certificate=no output=user as-value \
            http-header-field="Authorization: Bearer $TOKEN,Content-Type: application/json" \
            http-data="{\"type\":\"A\",\"name\":\"$RECORDNAME\",\"content\":\"$IP4NEW\",\"ttl\":120,\"proxied\":true}"]
        :set IP4CUR $IP4NEW
        :log info "CF-DDNS: Host $RECORDNAME updated with IP $IP4CUR"
    }  else={
        :log info "CF-DDNS: Previous IP $IP4NEW not changed, quitting"
    }
} else={
    :log info "CF-DDNS: $WANIF is not currently running, quitting"
}