#!/bin/bash

echo "Backing up Docker networks"
echo "--------------------------"

# Check if we have selected networks, otherwise backup all custom networks
if [ -n "${selected_networks}" ] && [ ${#selected_networks[@]} -gt 0 ]; then
    networks_to_backup=("${selected_networks[@]}")
    echo "Backing up selected networks: ${networks_to_backup[*]}"
else
    # Get all custom networks (exclude default bridge, host, none)
    networks_to_backup=($(docker network ls --format '{{.Name}}' | grep -v '^bridge$\|^host$\|^none$'))
    echo "Backing up all custom networks"
fi

# Create the backup directory
mkdir -p "$backup_path"/networks

if [ ${#networks_to_backup[@]} -eq 0 ]; then
    echo "No custom networks found to backup"
    echo ""
    return 0
fi

for network_name in "${networks_to_backup[@]}"
do
    echo -n "$network_name - "

    # Check if network exists
    if ! docker network ls --format '{{.Name}}' | grep -q "^$network_name$"; then
        echo "NOT FOUND (skipped)"
        continue
    fi

    # Get network inspection data
    network_data=$(docker network inspect "$network_name" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$network_data" ]; then
        echo "$network_data" > "$backup_path/networks/$network_name-network.json"
        echo "OK"
    else
        echo "FAILED"
    fi
done

echo ""
