#!/bin/bash

echo "Restoring Docker networks"
echo "-------------------------"

# Check if we have selected networks, otherwise restore all
if [ -n "${selected_networks}" ] && [ ${#selected_networks[@]} -gt 0 ]; then
    networks_to_restore=("${selected_networks[@]}")
    echo "Restoring selected networks: ${networks_to_restore[*]}"
else
    # Get all network backup files
    networks_to_restore=()
    if [ -d "$backup_path/networks" ]; then
        for network_file in "$backup_path/networks"/*-network.json; do
            if [ -f "$network_file" ]; then
                network_name=$(basename "$network_file" -network.json)
                networks_to_restore+=("$network_name")
            fi
        done
    fi
    echo "Restoring all networks from backup"
fi

if [ ${#networks_to_restore[@]} -eq 0 ]; then
    echo "No networks to restore"
    echo ""
    return 0
fi

for network_name in "${networks_to_restore[@]}"
do
    echo -n "$network_name - "

    network_file="$backup_path/networks/$network_name-network.json"

    # Check if backup file exists
    if [ ! -f "$network_file" ]; then
        echo "BACKUP NOT FOUND (skipped)"
        continue
    fi

    # Check if network already exists
    if docker network ls --format '{{.Name}}' | grep -q "^$network_name$"; then
        echo "EXISTS (skipping)"
        continue
    fi

    # Read network configuration
    network_data=$(cat "$network_file")

    # Parse network configuration using jq if available, otherwise use fallback
    if command -v jq >/dev/null 2>&1; then
        # Use jq for reliable JSON parsing
        driver=$(echo "$network_data" | jq -r '.[0].Driver // "bridge"' 2>/dev/null)
        subnet=$(echo "$network_data" | jq -r '.[0].IPAM.Config[0].Subnet // empty' 2>/dev/null)
        gateway=$(echo "$network_data" | jq -r '.[0].IPAM.Config[0].Gateway // empty' 2>/dev/null)
        ip_range=$(echo "$network_data" | jq -r '.[0].IPAM.Config[0].IPRange // empty' 2>/dev/null)

        # Get network options
        enable_icc=$(echo "$network_data" | jq -r '.[0].Options."com.docker.network.bridge.enable_icc" // empty' 2>/dev/null)
        enable_ip_masquerade=$(echo "$network_data" | jq -r '.[0].Options."com.docker.network.bridge.enable_ip_masquerade" // empty' 2>/dev/null)
        host_binding_ipv4=$(echo "$network_data" | jq -r '.[0].Options."com.docker.network.bridge.host_binding_ipv4" // empty' 2>/dev/null)

        # Check if this is an overlay network (swarm)
        scope=$(echo "$network_data" | jq -r '.[0].Scope // "local"' 2>/dev/null)

    else
        # Fallback parsing using grep/sed
        echo "Warning: jq not found, using basic parsing"
        driver=$(echo "$network_data" | grep -o '"Driver"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"Driver"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        subnet=$(echo "$network_data" | grep -o '"Subnet"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"Subnet"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        gateway=$(echo "$network_data" | grep -o '"Gateway"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"Gateway"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        scope=$(echo "$network_data" | grep -o '"Scope"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"Scope"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

        enable_icc=""
        enable_ip_masquerade=""
        host_binding_ipv4=""
        ip_range=""
    fi

    # Skip swarm/overlay networks as they require swarm mode
    if [ "$scope" = "swarm" ] || [ "$driver" = "overlay" ]; then
        echo "SWARM NETWORK (skipped - requires swarm mode)"
        continue
    fi

    # Set default driver if empty
    if [ -z "$driver" ] || [ "$driver" = "null" ]; then
        driver="bridge"
    fi

    # Build docker network create command
    create_cmd="docker network create"

    # Add driver
    create_cmd="$create_cmd --driver=$driver"

    # Add subnet and gateway if specified
    if [ -n "$subnet" ] && [ "$subnet" != "null" ] && [ "$subnet" != "" ]; then
        ipam_opts="--subnet=$subnet"

        if [ -n "$gateway" ] && [ "$gateway" != "null" ] && [ "$gateway" != "" ]; then
            ipam_opts="$ipam_opts --gateway=$gateway"
        fi

        if [ -n "$ip_range" ] && [ "$ip_range" != "null" ] && [ "$ip_range" != "" ]; then
            ipam_opts="$ipam_opts --ip-range=$ip_range"
        fi

        create_cmd="$create_cmd $ipam_opts"
    fi

    # Add bridge options if this is a bridge network
    if [ "$driver" = "bridge" ]; then
        if [ -n "$enable_icc" ] && [ "$enable_icc" != "null" ]; then
            create_cmd="$create_cmd --opt com.docker.network.bridge.enable_icc=$enable_icc"
        fi

        if [ -n "$enable_ip_masquerade" ] && [ "$enable_ip_masquerade" != "null" ]; then
            create_cmd="$create_cmd --opt com.docker.network.bridge.enable_ip_masquerade=$enable_ip_masquerade"
        fi

        if [ -n "$host_binding_ipv4" ] && [ "$host_binding_ipv4" != "null" ]; then
            create_cmd="$create_cmd --opt com.docker.network.bridge.host_binding_ipv4=$host_binding_ipv4"
        fi
    fi

    # Add network name
    create_cmd="$create_cmd $network_name"

    # Execute the command
    eval "$create_cmd" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "FAILED"
        echo "Command: $create_cmd"
    fi
done

echo ""
