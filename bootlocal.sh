#!/bin/sh

network="eth0"
ip=""
netmask="255.255.255.0"
gateway=""
ssh_port="22"
nameservers=""

parse_parameter() {
    for x in $(cat /proc/cmdline); do
        case "$x" in
            password=*)
                value=$(echo "$x" | cut -d'=' -f2-)
                echo "tc:$value" | chpasswd
                ;;
            ip=*)
                ip=$(echo "$x" | cut -d'=' -f2-)
                ;;
            netmask=*)
                netmask=$(echo "$x" | cut -d'=' -f2-)
                ;;
            gateway=*)
                gateway=$(echo "$x" | cut -d'=' -f2-)
                ;;
            nameserver=*)
                nameservers=$(echo "$x" | cut -d'=' -f2-)
                ;;
            ssh_port=*)
                ssh_port=$(echo "$x" | cut -d'=' -f2-)
                ;;
        esac
    done
}

configure_network() {
    if [ -n "$ip" ]; then
        echo "Configuring static IP: $ip"
        ifconfig "$network" "$ip" netmask "$netmask"
        ifconfig "$network" up
        [ -n "$gateway" ] && route add default gw "$gateway" "$network"
    else
        echo "Auto configuring $network (DHCP)"
        /sbin/udhcpc -i "$network" -n -q
    fi

    if [ -n "$nameservers" ]; then
        echo "Configuring nameservers: $nameservers"
        : > /etc/resolv.conf
        echo "$nameservers" | tr ',' '\n' | while read ns; do
            [ -n "$ns" ] && echo "nameserver $ns" >> /etc/resolv.conf
        done
    fi
}

configure_ssh() {
    if [ -n "$ssh_port" ]; then
        echo "Configuring SSH on port: $ssh_port"
        sed -i "s/^#Port 22/Port $ssh_port/" /usr/local/etc/ssh/sshd_config
        sed -i "s/^Port [0-9]*/Port $ssh_port/" /usr/local/etc/ssh/sshd_config
    fi
}

parse_parameter
configure_network
configure_ssh
/usr/local/etc/init.d/openssh start
