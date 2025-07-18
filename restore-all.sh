# Initialize selection arrays
selected_containers=()
selected_volumes=()
selected_images=()
selected_networks=()

if [ "$non_interactive" = false ]
then
  echo "Restore networks ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific networks"
  read -r restore_networks

  echo "Restore container images ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific images"
  read -r restore_images

  echo "Restore volumes ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific volumes"
  read -r restore_volumes

  echo "Restore containers ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific containers"
  read -r restore_containers
else
  restore_networks="y"
  restore_images="y"
  restore_volumes="y"
  restore_containers="y"
fi

# Handle selective network restore
if [ "$restore_#!/bin/bash

echo "Starting docker restore"
echo ""

# Check if backup path exists
if [ ! -d "$backup_path" ]
then
  echo "Error: backup path does not exist"
  exit 1
fi

# Check if this is a compressed backup
if [ -f "$backup_path.tar.gz" ] && [ ! -d "$backup_path" ]
then
  echo "Found compressed backup, extracting..."
  tar -xzf "$backup_path.tar.gz" -C "$(dirname "$backup_path")"
  echo "Extraction complete"
  echo ""
fi

# Function to select containers from backup
select_containers_from_backup() {
    echo "Available containers in backup:"
    echo "------------------------------"
    containers=()

    # Find container directories in backup
    for container_dir in "$backup_path"/*; do
        if [ -d "$container_dir" ] && [ "$(basename "$container_dir")" != "volumes" ] && [ "$(basename "$container_dir")" != "networks" ]; then
            container_name=$(basename "$container_dir")
            # Check if it has container data
            if [ -f "$container_dir/$container_name-data.txt" ]; then
                containers+=("$container_name")
            fi
        fi
    done

    if [ ${#containers[@]} -eq 0 ]; then
        echo "No containers found in backup"
        return 1
    fi

    for i in "${!containers[@]}"; do
        echo "$((i+1)). ${containers[$i]}"
    done
    echo "$((${#containers[@]}+1)). All containers"
    echo "$((${#containers[@]}+2)). Cancel"
    echo ""

    while true; do
        echo -n "Select containers to restore (comma-separated numbers, e.g., 1,3,5): "
        read -r selection

        if [ "$selection" = "$((${#containers[@]}+2))" ]; then
            return 1
        elif [ "$selection" = "$((${#containers[@]}+1))" ]; then
            selected_containers=("${containers[@]}")
            return 0
        else
            selected_containers=()
            IFS=',' read -ra ADDR <<< "$selection"
            for num in "${ADDR[@]}"; do
                num=$(echo "$num" | xargs) # trim whitespace
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#containers[@]}" ]; then
                    selected_containers+=("${containers[$((num-1))]}")
                else
                    echo "Invalid selection: $num"
                    continue 2
                fi
            done
            return 0
        fi
    done
}

# Function to select volumes from backup
select_volumes_from_backup() {
    echo "Available volumes in backup:"
    echo "---------------------------"
    volumes=()

    # Find volume files in backup
    if [ -d "$backup_path/volumes" ]; then
        for volume_file in "$backup_path/volumes"/*.tar.gz; do
            if [ -f "$volume_file" ]; then
                volume_name=$(basename "$volume_file" .tar.gz)
                volumes+=("$volume_name")
            fi
        done
    fi

    if [ ${#volumes[@]} -eq 0 ]; then
        echo "No volumes found in backup"
        return 1
    fi

    for i in "${!volumes[@]}"; do
        echo "$((i+1)). ${volumes[$i]}"
    done
    echo "$((${#volumes[@]}+1)). All volumes"
    echo "$((${#volumes[@]}+2)). Cancel"
    echo ""

    while true; do
        echo -n "Select volumes to restore (comma-separated numbers, e.g., 1,3,5): "
        read -r selection

        if [ "$selection" = "$((${#volumes[@]}+2))" ]; then
            return 1
        elif [ "$selection" = "$((${#volumes[@]}+1))" ]; then
            selected_volumes=("${volumes[@]}")
            return 0
        else
            selected_volumes=()
            IFS=',' read -ra ADDR <<< "$selection"
            for num in "${ADDR[@]}"; do
                num=$(echo "$num" | xargs) # trim whitespace
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#volumes[@]}" ]; then
                    selected_volumes+=("${volumes[$((num-1))]}")
                else
                    echo "Invalid selection: $num"
                    continue 2
                fi
            done
            return 0
        fi
    done
}

# Function to select images from backup
select_images_from_backup() {
    echo "Available images in backup:"
    echo "--------------------------"
    images=()

    # Find image files in backup
    for container_dir in "$backup_path"/*; do
        if [ -d "$container_dir" ] && [ "$(basename "$container_dir")" != "volumes" ] && [ "$(basename "$container_dir")" != "networks" ]; then
            container_name=$(basename "$container_dir")
            if [ -f "$container_dir/$container_name-image.tar" ]; then
                images+=("$container_name")
            fi
        fi
    done

    if [ ${#images[@]} -eq 0 ]; then
        echo "No images found in backup"
        return 1
    fi

    for i in "${!images[@]}"; do
        echo "$((i+1)). ${images[$i]} (image)"
    done
    echo "$((${#images[@]}+1)). All images"
    echo "$((${#images[@]}+2)). Cancel"
    echo ""

    while true; do
        echo -n "Select images to restore (comma-separated numbers, e.g., 1,3,5): "
        read -r selection

        if [ "$selection" = "$((${#images[@]}+2))" ]; then
            return 1
        elif [ "$selection" = "$((${#images[@]}+1))" ]; then
            selected_images=("${images[@]}")
            return 0
        else
            selected_images=()
            IFS=',' read -ra ADDR <<< "$selection"
            for num in "${ADDR[@]}"; do
                num=$(echo "$num" | xargs) # trim whitespace
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#images[@]}" ]; then
                    selected_images+=("${images[$((num-1))]}")
                else
                    echo "Invalid selection: $num"
                    continue 2
                fi
            done
            return 0
        fi
    done
}

# Function to select networks from backup
select_networks_from_backup() {
    echo "Available networks in backup:"
    echo "----------------------------"
    networks=()

    # Find network files in backup
    if [ -d "$backup_path/networks" ]; then
        for network_file in "$backup_path/networks"/*-network.json; do
            if [ -f "$network_file" ]; then
                network_name=$(basename "$network_file" -network.json)
                networks+=("$network_name")
            fi
        done
    fi

    if [ ${#networks[@]} -eq 0 ]; then
        echo "No networks found in backup"
        return 1
    fi

    for i in "${!networks[@]}"; do
        echo "$((i+1)). ${networks[$i]}"
    done
    echo "$((${#networks[@]}+1)). All networks"
    echo "$((${#networks[@]}+2)). Cancel"
    echo ""

    while true; do
        echo -n "Select networks to restore (comma-separated numbers, e.g., 1,3,5): "
        read -r selection

        if [ "$selection" = "$((${#networks[@]}+2))" ]; then
            return 1
        elif [ "$selection" = "$((${#networks[@]}+1))" ]; then
            selected_networks=("${networks[@]}")
            return 0
        else
            selected_networks=()
            IFS=',' read -ra ADDR <<< "$selection"
            for num in "${ADDR[@]}"; do
                num=$(echo "$num" | xargs) # trim whitespace
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#networks[@]}" ]; then
                    selected_networks+=("${networks[$((num-1))]}")
                else
                    echo "Invalid selection: $num"
                    continue 2
                fi
            done
            return 0
        fi
    done
}

# Initialize selection arrays
selected_containers=()
selected_volumes=()
selected_images=()

if [ "$non_interactive" = false ]
then
  echo "Restore container images ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific images"
  read -r restore_images

  echo "Restore volumes ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific volumes"
  read -r restore_volumes

  echo "Restore containers ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific containers"
  read -r restore_containers
else
  restore_images="y"
  restore_volumes="y"
  restore_containers="y"
fi

# Handle selective image restore
if [ "$restore_images" = "s" ]
then
  if select_images_from_backup; then
    restore_images="y"
    export selected_images
  else
    restore_images="n"
  fi
fi

# Handle selective volume restore
if [ "$restore_volumes" = "s" ]
then
  if select_volumes_from_backup; then
    restore_volumes="y"
    export selected_volumes
  else
    restore_volumes="n"
  fi
fi

# Handle selective container restore
if [ "$restore_containers" = "s" ]
then
  if select_containers_from_backup; then
    restore_containers="y"
    export selected_containers
  else
    restore_containers="n"
  fi
fi

if [ "$restore_images" = "y" ]
then
  source restore/restore-images.sh
fi

if [ "$restore_volumes" = "y" ]
then
  source restore/restore-volumes.sh
fi

if [ "$restore_containers" = "y" ]
then
  source restore/restore-containers.sh
fi

echo ""
echo "Restoration finished"
echo ""
echo "Summary:"
echo "--------"
if [ "$restore_images" = "y" ]; then
    if [ -n "${selected_images}" ] && [ ${#selected_images[@]} -gt 0 ]; then
        echo "Restored images: ${#selected_images[@]} selected (${selected_images[*]})"
    else
        echo "Restored images: All available"
    fi
fi

if [ "$restore_volumes" = "y" ]; then
    if [ -n "${selected_volumes}" ] && [ ${#selected_volumes[@]} -gt 0 ]; then
        echo "Restored volumes: ${#selected_volumes[@]} selected (${selected_volumes[*]})"
    else
        echo "Restored volumes: All available"
    fi
fi

if [ "$restore_containers" = "y" ]; then
    if [ -n "${selected_containers}" ] && [ ${#selected_containers[@]} -gt 0 ]; then
        echo "Restored containers: ${#selected_containers[@]} selected (${selected_containers[*]})"
    else
        echo "Restored containers: All available"
    fi
fi

echo "Running containers: $(docker ps --format '{{.Names}}' | wc -l)"
