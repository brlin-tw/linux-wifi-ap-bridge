#!/usr/bin/env bash
# Configure a soft Wi-Fi access point that bridges with the ethernet interface
#
# Copyright 2026 Buo-ren Lin <buo.ren.lin@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
set \
    -o errexit \
    -o nounset

BRIDGE_INTERFACE="${BRIDGE_INTERFACE:-wifi-br0}"
ETHERNET_INTERFACE="${ETHERNET_INTERFACE:-eth0}"
WIFI_INTERFACE="${WIFI_INTERFACE:-wlan0}"
WIFI_AP_SSID="${WIFI_AP_SSID:-'Bridged AP'}"
WIFI_AP_PSK="${WIFI_AP_PSK:-}"

if test "${EUID}" -ne 0; then
    printf \
        'Error: This program requires to be run as the superuser(root).\n' \
        1>&2
    exit 1
fi

if test -z "${WIFI_AP_PSK}"; then
    printf \
        'Error: WIFI_AP_PSK is not set.\n' \
        1>&2
    exit 1
fi

# FIXME: No idempotent and error checking logic
nmcli connection add type bridge con-name 'Bridge for software Wi-Fi AP in bridge mode' ifname "${BRIDGE_INTERFACE}"

# FIXME: No idempotent and error checking logic
nmcli connection add type bridge-slave con-name 'Ethernet bridge port for software Wi-Fi AP' ifname "${ETHERNET_INTERFACE}" master "${BRIDGE_INTERFACE}"

# FIXME: No idempotent and error checking logic
nmcli connection add type wifi con-name 'Wifi AP in bridge mode' ifname "${WIFI_AP_SSID}" master wifi-br0 ssid "${WIFI_AP_SSID}"

# FIXME: No idempotent and error checking logic
nmcli connection modify 'Wifi AP in bridge mode' wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${WIFI_AP_PSK}"

# FIXME: No idempotent and error checking logic
nmcli connection up 'Bridge for software Wi-Fi AP in bridge mode'
nmcli connection up 'Ethernet bridge port for software Wi-Fi AP'
nmcli connection up 'Wifi AP in bridge mode'

# FIXME: No idempotent and error checking logic
iptables -P FORWARD ACCEPT
