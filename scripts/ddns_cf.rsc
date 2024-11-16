# DDNS for Cloudflare

# Update Cloudflare DNS IPv4 address script
# RouterOS version >= 7.x is required

# ** CONFIGURE SECTION **

# WAN IPv4 interface
:local wanif    "Wan3"

# Cloudflare section
:local email       ""
:local key         ""
:local zoneID      ""
:local recordsID   ""

# Domain hostname
:local hostName ""

# DNS server for resolution
:local dnsServer "1.1.1.1"

# ** END OF CONFIGURE SECTION **

# Get WAN interface IPv4 address
:local ip4new [/ip address get [/ip address find interface=$wanif] address]
:set ip4new [:pick [:tostr $ip4new] 0 [:find [:tostr $ip4new] "/"]]

:if ([:len $ip4new] = 0) do={
  :log error "[Cloudflare DDNS] Could not get IPv4 for interface $wanif"
  :error "[Cloudflare DDNS] Could not get IPv4 for interface $wanif"
}

# Use DNS resolve with specified server to get current IP address of the domain
:local resolvedIp [:resolve $hostName server=$dnsServer]

:if ($resolvedIp = "") do={
  :log error "[Cloudflare DDNS] Could not resolve $hostName using server $dnsServer"
  :error "[Cloudflare DDNS] Could not resolve $hostName using server $dnsServer"
}

:log info "[Cloudflare DDNS] DNS resolved IP for $hostName: $resolvedIp"
:log info "[Cloudflare DDNS] Current WAN IPv4 address: $ip4new"

:if ($ip4new = $resolvedIp) do={
  :log info "[Cloudflare DDNS] WAN IPv4 address for interface $wanif and DNS resolved IP are the same, no update needed."
} else {
  :log info "[Cloudflare DDNS] WAN IPv4 address for interface $wanif has been changed to $ip4new."

  :local url    "https://api.cloudflare.com/client/v4/zones/$zoneID/dns_records/$recordsID"
  :local header "X-Auth-Email: $email, X-Auth-Key: $key, content-type: application/json"
  :local data   "{\"type\":\"A\",\"name\":\"$hostName\",\"content\":\"$ip4new\",\"ttl\":60}"

  :log info "[Cloudflare DDNS] URL: $url"
  :log info "[Cloudflare DDNS] HEADER: $header"
  :log info "[Cloudflare DDNS] DATA: $data"
  :log info "[Cloudflare DDNS] Updating host $hostName address."

  :local jsonAnswer [/tool fetch mode=https http-method=put http-header-field=$header http-data=$data url=$url as-value output=user]

  :if ([:len $jsonAnswer] > 0) do={

    /system script run "JParseFunctions"; local JSONLoads; local JSONUnload
    :local result ([$JSONLoads ($jsonAnswer->"data")]->"success")
    $JSONUnload

    :if ($result = true) do={
      :log info "[Cloudflare DDNS] Successfully updated IPv4 address to $ip4new."
    } else {
      :log error "[Cloudflare DDNS] Error while updating IPv4 address."
    }
  } else {
    :log error "[Cloudflare DDNS] No answer from Cloudflare API."
  }
}
