# Mikrotik RouterOS 配置

## 概述

安装

## 0. 创建列表
    /interface list
    add name=LAN
    add name=WAN
    /interface list member
    add interface=<Interface1> list=WAN
    add interface=<Interface2> list=LAN


## 1. 添加一个用户并配置admin 用户只允许内网连接
使用winbox 登录连接，/system/Users 添加和配置

![配置用户](https://git.c0despace.uk/https://raw.githubusercontent.com/zywj0han9/Img-bed/master/imgs/RouterOS_user_set.png)

## 2. 禁用neighbor发现协议
    /ip neighbor discovery-settings set discover-interface-list=none 

## 3. 禁用带宽测试服务
    /tool bandwidth-server set enabled=no 

## 4. (可选) 禁用DNS cache
    /ip dns set allow-remote-requests=no

## 5. 禁用proxy
    /ip proxy set enabled=no

## 6. 禁用socks    
    /ip socks set enabled=no

## 7. 禁用upnp
    /ip upnp set enabled=no

## 8. 禁用cloud
    /ip cloud set ddns-enabled=no update-time=no

## 9. 启用更安全的SSH访问
    /ip ssh set strong-crypto=yes

## 10. 建立防火墙
    
### 10.1 接受已建立和相关的连接
    /ip firewall filter
    add chain=input connection-state=established,related,untracked action=accept comment="Allow Established/Related/Untracked connections"


### 10.2 丢弃无效链接，并允许已建立，相关和未跟踪的链接:
    /ip firewall filter
    add chain=input connection-state=invalid action=drop comment="Drop Invalid connections"

### 10.3 允许内网主机访问路由
    /ip firewall address-list
    add address=192.168.2.1-192.168.2.254 list=allowed_to_router
    /ip firewall filter
    add action=accept chain=input src-address-list=allowed_to_router
    add action=accept chain=input protocol=icmp
    add action=drop chain=input

### 10.4 保护局域网设备
    /ip firewall address-list
    add address=0.0.0.0/8 comment=RFC6890 list=not_in_internet
    add address=172.16.0.0/12 comment=RFC6890 list=not_in_internet
    add address=192.168.0.0/16 comment=RFC6890 list=not_in_internet
    add address=10.0.0.0/8 comment=RFC6890 list=not_in_internet
    add address=169.254.0.0/16 comment=RFC6890 list=not_in_internet
    add address=127.0.0.0/8 comment=RFC6890 list=not_in_internet
    add address=224.0.0.0/4 comment=Multicast list=not_in_internet
    add address=198.18.0.0/15 comment=RFC6890 list=not_in_internet
    add address=192.0.0.0/24 comment=RFC6890 list=not_in_internet
    add address=192.0.2.0/24 comment=RFC6890 list=not_in_internet
    add address=198.51.100.0/24 comment=RFC6890 list=not_in_internet
    add address=203.0.113.0/24 comment=RFC6890 list=not_in_internet
    add address=100.64.0.0/10 comment=RFC6890 list=not_in_internet
    add address=240.0.0.0/4 comment=RFC6890 list=not_in_internet
    add address=192.88.99.0/24 comment="6to4 relay Anycast [RFC 3068]" list=not_in_internet

    /ip firewall filter
    add action=fasttrack-connection chain=forward comment=FastTrack connection-state=established,related
    add action=accept chain=forward comment="Established, Related" connection-state=established,related
    add action=drop chain=forward comment="Drop invalid" connection-state=invalid log=yes log-prefix=invalid
    add action=drop chain=forward comment="Drop tries to reach not public addresses from LAN" dst-address-list=not_in_internet in-interface-list=LAN log=yes log-prefix=!public_from_LAN out-interface-list=LAN
    add action=drop chain=forward comment="Drop incoming packets that are not NAT`ted" connection-nat-state=!dstnat connection-state=new in-interface-list=WAN log=yes log-prefix=!NAT 
    add action=jump chain=forward protocol=icmp jump-target=icmp comment="jump to ICMP filters" 
    add action=drop chain=forward comment="Drop incoming from internet which is not public IP" in-interface-list=WAN log=yes log-prefix=!public src-address-list=not_in_internet 
    add action=drop chain=forward comment="Drop packets from LAN that do not have LAN IP" in-interface-list=LAN log=yes log-prefix=LAN_!LAN src-address=!192.168.2.0/24

## 10.5 仅允许 ICMP
    /ip firewall filter
    add chain=icmp protocol=icmp icmp-options=0:0 action=accept \
        comment="echo reply"
    add chain=icmp protocol=icmp icmp-options=3:0 action=accept \
        comment="net unreachable"
    add chain=icmp protocol=icmp icmp-options=3:1 action=accept \
        comment="host unreachable"
    add chain=icmp protocol=icmp icmp-options=3:4 action=accept \
        comment="host unreachable fragmentation required"
    add chain=icmp protocol=icmp icmp-options=8:0 action=accept \
        comment="allow echo request"
    add chain=icmp protocol=icmp icmp-options=11:0 action=accept \
        comment="allow time exceed"
    add chain=icmp protocol=icmp icmp-options=12:0 action=accept \
        comment="allow parameter bad"
    add chain=icmp action=drop comment="deny all other types"

## 10.6 IPV6

    /ipv6 firewall address-list add address=fd12:672e:6f65:8899::/64 list=allowed
    /ipv6 firewall filter
    add action=accept chain=input comment="allow established and related" connection-state=established,related
    add chain=input action=accept protocol=icmpv6 comment="accept ICMPv6"
    add chain=input action=accept protocol=udp port=33434-33534 comment="defconf: accept UDP traceroute"
    add chain=input action=accept protocol=udp dst-port=546 src-address=fe80::/10 comment="accept DHCPv6-Client prefix delegation."
    add action=drop chain=input in-interface=in_interface_name log=yes log-prefix=dropLL_from_public src-address=fe80::/10
    add action=accept chain=input comment="allow allowed addresses" src-address-list=allowed
    add action=drop chain=input
    /ipv6 firewall address-list
    add address=fe80::/16 list=allowed
    add address=ff02::/16 comment=multicast list=allowed
    /ipv6 firewall filter
    add action=accept chain=forward comment=established,related connection-state=established,related
    add action=drop chain=forward comment=invalid connection-state=invalid log=yes log-prefix=ipv6,invalid
    add action=accept chain=forward comment=icmpv6 in-interface=!in_interface_name protocol=icmpv6
    add action=accept chain=forward comment="local network" in-interface=!in_interface_name src-address-list=allowed
    add action=drop chain=forward log-prefix=IPV6

## 10.7 DDOS 防护
    /ip firewall address-list
    add list=ddos-attackers
    add list=ddos-targets
    add address=192.168.2.0/24 list=ddos-whitelist comment="Whitelist for internal IPs"

    /ip firewall raw
    # 内网白名单规则
    add chain=prerouting src-address-list=ddos-whitelist action=accept comment="Allow internal IPs bypass DDoS rules"
    add chain=prerouting dst-address-list=ddos-whitelist action=accept comment="Allow internal IPs bypass DDoS rules"
    add chain=prerouting src-address-list=dns-list action=accept comment="Allow internal IPs bypass DDoS rules"

    /ip firewall filter
    add chain=forward src-address-list=ddos-whitelist action=accept comment="Allow traffic from whitelisted IPs"
    add chain=forward dst-address-list=ddos-whitelist action=accept comment="Allow traffic to whitelisted IPs"
    add chain=forward src-address-list=dns-list action=accept comment="Allow traffic from whitelisted IPs"
    add action=return chain=detect-ddos dst-limit=1024,1024,src-and-dst-addresses/10s
    add action=add-dst-to-address-list address-list=ddos-targets address-list-timeout=10m chain=detect-ddos
    add action=add-src-to-address-list address-list=ddos-attackers address-list-timeout=10m chain=detect-ddos
    add chain=forward connection-state=new action=jump jump-target=detect-ddos
    add chain=detect-ddos dst-limit=1024,1024,src-and-dst-addresses/10s action=return
    
    /ip firewall raw
    add action=drop chain=prerouting dst-address-list=ddos-targets src-address-list=ddos-attackers
    add chain=prerouting src-address-list=!ddos-attackers packet-rate=100 action=add-src-to-address-list address-list=ddos-attackers address-list-timeout=10m comment="Detect DDoS attackers"
    add chain=prerouting src-address-list=ddos-attackers action=drop comment="Drop DDoS attackers"

## 10.8 SSH 防暴力破解
    /ip firewall filter
    # 第一次尝试：加入 SSH-1 列表，超时 5 分钟
    add action=add-src-to-address-list address-list=SSH-1 address-list-timeout=5m chain=input comment="First attempt" connection-state=new dst-port=22 protocol=tcp

    # 第二次尝试：如果在 SSH-1 列表中，再加入 SSH-2 列表，超时 15 分钟
    add action=add-src-to-address-list address-list=SSH-2 address-list-timeout=15m chain=input comment="Second attempt" connection-state=new dst-port=22 protocol=tcp src-address-list=SSH-1

    # 第三次尝试：如果在 SSH-2 列表中，再加入 SSH-3 列表，超时 1 小时
    add action=add-src-to-address-list address-list=SSH-3 address-list-timeout=1h chain=input comment="Third attempt" connection-state=new dst-port=22 protocol=tcp src-address-list=SSH-2

    # 超过三次尝试：加入 bruteforce_blacklist，封禁 1 天
    add action=add-src-to-address-list address-list=bruteforce_blacklist address-list-timeout=1d chain=input comment="Blacklist after three attempts" connection-state=new dst-port=22 protocol=tcp src-address-list=SSH-3

    # 允许非黑名单 IP 访问 SSH
    add action=accept chain=input dst-port=22 protocol=tcp src-address-list=!bruteforce_blacklist comment="Allow SSH from non-blacklisted IPs"

    # 默认丢弃其他 SSH 流量
    add action=drop chain=input dst-port=22 protocol=tcp comment="Drop SSH from blacklisted IPs"