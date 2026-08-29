#!/usr/bin/env bash
# Configure a soft Wi-Fi access point that bridges with the ethernet interface
#
# Copyright 2026 Buo-ren Lin <buo.ren.lin@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
BRIDGE_INTERFACE="${BRIDGE_INTERFACE:-wifi-br0}"
WIFI_AP_SSID="${WIFI_AP_SSID:-'Bridged AP'}"
WIFI_AP_PSK="${WIFI_AP_PSK:-}"

set_opts=(
    -o errexit
    -o nounset
)
if ! set "${set_opts[@]}"; then
    printf \
        'Error: Unable to set shell options: %s\n' \
        "${set_opts[*]}" \
        1>&2
    exit 1
fi

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

required_commands=(
    awk
    iptables
    nmcli
)
for command in "${required_commands[@]}"; do
    if ! command -v "${command}" >/dev/null; then
        printf \
            'Error: This program requires the "%s" command to be available in your command search PATHs.\n' \
            "${command}" \
            1>&2
        exit 1
    fi
done

if ! test -v ETHERNET_INTERFACE; then
    printf \
        'Info: Auto-detecting Ethernet interface...\n'
    mapfile -t detected_ethernet_interfaces < <(
        nmcli -t -f DEVICE,TYPE device \
            | awk -F: '$2=="ethernet"{print $1}'
    )
    if test "${#detected_ethernet_interfaces[@]}" -eq 0; then
        printf \
            'Error: No Ethernet interface detected. Please specify ETHERNET_INTERFACE.\n' \
            1>&2
        exit 1
    elif test "${#detected_ethernet_interfaces[@]}" -gt 1; then
        printf \
            'Error: Multiple Ethernet interfaces detected (%s). Please specify ETHERNET_INTERFACE explicitly.\n' \
            "${detected_ethernet_interfaces[*]}" \
            1>&2
        exit 1
    fi
    ETHERNET_INTERFACE="${detected_ethernet_interfaces[0]}"
    printf \
        'Info: Detected Ethernet interface: %s\n' \
        "${ETHERNET_INTERFACE}"
fi

if ! test -v WIFI_INTERFACE; then
    printf \
        'Info: Auto-detecting Wi-Fi interface...\n'
    mapfile -t detected_wifi_interfaces < <(
        nmcli -t -f DEVICE,TYPE device \
            | awk -F: '$2=="wifi"{print $1}'
    )
    if test "${#detected_wifi_interfaces[@]}" -eq 0; then
        printf \
            'Error: No Wi-Fi interface detected. Please specify WIFI_INTERFACE.\n' \
            1>&2
        exit 1
    elif test "${#detected_wifi_interfaces[@]}" -gt 1; then
        printf \
            'Error: Multiple Wi-Fi interfaces detected (%s). Please specify WIFI_INTERFACE explicitly.\n' \
            "${detected_wifi_interfaces[*]}" \
            1>&2
        exit 1
    fi
    WIFI_INTERFACE="${detected_wifi_interfaces[0]}"
    printf \
        'Info: Detected Wi-Fi interface: %s\n' \
        "${WIFI_INTERFACE}"
fi

bridge_con_name='Bridge for software Wi-Fi AP in bridge mode'
ethernet_con_name='Ethernet bridge port for software Wi-Fi AP'
wifi_con_name='Wifi AP in bridge mode'

if ! nmcli connection show "${bridge_con_name}" >/dev/null 2>&1; then
    printf \
        'Info: Creating bridge connection "%s"...\n' \
        "${bridge_con_name}"
    if ! nmcli connection add \
        type bridge \
        con-name "${bridge_con_name}" \
        ifname "${BRIDGE_INTERFACE}"; then
        printf \
            'Error: Unable to add bridge connection "%s".\n' \
            "${bridge_con_name}" \
            1>&2
        exit 2
    fi
else
    printf \
        'Info: Bridge connection "%s" already exists, updating configuration...\n' \
        "${bridge_con_name}"
    if ! nmcli connection modify \
        "${bridge_con_name}" \
        connection.interface-name "${BRIDGE_INTERFACE}"; then
        printf \
            'Error: Unable to modify bridge connection "%s".\n' \
            "${bridge_con_name}" \
            1>&2
        exit 2
    fi
fi

if ! nmcli connection show "${ethernet_con_name}" >/dev/null 2>&1; then
    printf \
        'Info: Creating Ethernet bridge port connection "%s"...\n' \
        "${ethernet_con_name}"
    if ! nmcli connection add \
        type bridge-slave \
        con-name "${ethernet_con_name}" \
        ifname "${ETHERNET_INTERFACE}" \
        master "${BRIDGE_INTERFACE}"; then
        printf \
            'Error: Unable to add Ethernet bridge port connection "%s".\n' \
            "${ethernet_con_name}" \
            1>&2
        exit 2
    fi
else
    printf \
        'Info: Ethernet bridge port connection "%s" already exists, updating configuration...\n' \
        "${ethernet_con_name}"
    if ! nmcli connection modify \
        "${ethernet_con_name}" \
        connection.interface-name "${ETHERNET_INTERFACE}" \
        connection.master "${BRIDGE_INTERFACE}" \
        connection.slave-type bridge; then
        printf \
            'Error: Unable to modify Ethernet bridge port connection "%s".\n' \
            "${ethernet_con_name}" \
            1>&2
        exit 2
    fi
fi

if ! nmcli connection show "${wifi_con_name}" >/dev/null 2>&1; then
    printf \
        'Info: Creating Wi-Fi AP connection "%s"...\n' \
        "${wifi_con_name}"
    if ! nmcli connection add \
        type wifi \
        mode ap \
        con-name "${wifi_con_name}" \
        ifname "${WIFI_INTERFACE}" \
        master "${BRIDGE_INTERFACE}" \
        ssid "${WIFI_AP_SSID}"; then
        printf \
            'Error: Unable to add Wi-Fi AP connection "%s".\n' \
            "${wifi_con_name}" \
            1>&2
        exit 2
    fi
else
    printf \
        'Info: Wi-Fi AP connection "%s" already exists, updating configuration...\n' \
        "${wifi_con_name}"
    if ! nmcli connection modify \
        "${wifi_con_name}" \
        connection.interface-name "${WIFI_INTERFACE}" \
        connection.master "${BRIDGE_INTERFACE}" \
        connection.slave-type bridge \
        802-11-wireless.mode ap \
        802-11-wireless.ssid "${WIFI_AP_SSID}"; then
        printf \
            'Error: Unable to modify Wi-Fi AP connection "%s".\n' \
            "${wifi_con_name}" \
            1>&2
        exit 2
    fi
fi

printf \
    'Info: Configuring security settings for Wi-Fi AP connection "%s"...\n' \
    "${wifi_con_name}"
if ! nmcli connection modify \
    "${wifi_con_name}" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "${WIFI_AP_PSK}"; then
    printf \
        'Error: Unable to configure security settings for "%s".\n' \
        "${wifi_con_name}" \
        1>&2
    exit 2
fi

printf \
    'Info: Activating connections...\n'
for con_name in \
    "${bridge_con_name}" \
    "${ethernet_con_name}" \
    "${wifi_con_name}"; do
    if ! nmcli connection up "${con_name}"; then
        printf \
            'Error: Unable to activate connection "%s".\n' \
            "${con_name}" \
            1>&2
        exit 2
    fi
done

printf \
    'Info: Configuring iptables forward policy...\n'
if ! iptables -P FORWARD ACCEPT; then
    printf \
        'Error: Unable to set iptables FORWARD policy to ACCEPT.\n' \
        1>&2
    exit 2
fi

printf \
    'Info: Operation completed without errors.\n'
