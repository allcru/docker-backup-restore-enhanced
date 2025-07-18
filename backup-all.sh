#!/bin/bash

echo "Starting docker backup"
echo "  - backup path: $backup_path"
echo "  - tar options: $tar_opts"
echo ""

# Check if backup path exists
if [ ! -d "$backup_path" ]
then
  # Attempt to create the directory
  if ! mkdir -p "$backup_path"
  then
    echo "Error: backup path does not exist and could not be created"
    exit 1
  fi
else
  # Check if backup path is empty
  if [ "$(ls -A "$backup_path")" ]
  then
    # Backup path is not empty
    if [ "$force" = false ]
    then
      echo "Error: backup path is not empty, use -f to force"
      exit 1
    else
      echo "Warning: backup path is not empty, but force flag is set"
    fi
  fi

  # Check if backup path is writable
  if ! touch "$backup_path/test.txt" 2>/dev/null
  then
    echo "Error: backup path is not writable"
    exit 1
  else
    rm "$backup_path/test.txt"
  fi
fi

# Function to select containers
select_containers() {
    echo "Available containers:"
    echo "--------------------"
    containers=($(docker ps --format '{{.Names}}' | sort))

    if [ ${#containers[@]} -eq 0 ]; then
        echo "No running containers found"
        return 1
    fi

    for i in "${!containers[@]}"; do
        echo "$((i+1)). ${containers[$i]}"
    done
    echo "$((${#containers[@]}+1)). All containers"
    echo "$((${#containers[@]}+2)). Cancel"
    echo ""

    while true; do
        echo -n "Select containers (comma-separated numbers, e.g., 1,3,5): "
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

# Function to select volumes
select_volumes() {
    echo "Available volumes:"
    echo "-----------------"
    volumes=($(docker volume ls -q | sort))

    if [ ${#volumes[@]} -eq 0 ]; then
        echo "No volumes found"
        return 1
    fi

    for i in "${!volumes[@]}"; do
        echo "$((i+1)). ${volumes[$i]}"
    done
    echo "$((${#volumes[@]}+1)). All volumes"
    echo "$((${#volumes[@]}+2)). Cancel"
    echo ""

    while true; do
        echo -n "Select volumes (comma-separated numbers, e.g., 1,3,5): "
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

# Function to select images
select_images() {
    echo "Available images (from running containers):"
    echo "------------------------------------------"
    images=($(docker ps --format '{{.Image}}' | sort -u))

    if [ ${#images[@]} -eq 0 ]; then
        echo "No container images found"
        return 1
    fi

    for i in "${!images[@]}"; do
        echo "$((i+1)). ${images[$i]}"
    done
    echo "$((${#images[@]}+1)). All images"
    echo "$((${#images[@]}+2)). Cancel"
    echo ""

    while true; do
        echo -n "Select images (comma-separated numbers, e.g., 1,3,5): "
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

# Function to select networks
select_networks() {
    echo "Available networks (custom networks only):"
    echo "------------------------------------------"
    networks=($(docker network ls --format '{{.Name}}' | grep -v '^bridge$\|^host$\|^none$' | sort))

    if [ ${#networks[@]} -eq 0 ]; then
        echo "No custom networks found"
        return 1
    fi

    for i in "${!networks[@]}"; do
        echo "$((i+1)). ${networks[$i]}"
    done
    echo "$((${#networks[@]}+1)). All networks"
    echo "$((${#networks[@]}+2)). Cancel"
    echo ""

    while true; do
        echo -n "Select networks (comma-separated numbers, e.g., 1,3,5): "
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
selected_networks=()

if [ "$non_interactive" = false ]
then
  echo "Backup container data (inspection output) ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific containers"
  read -r backup_container_data

  echo "Backup container images ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific images"
  read -r backup_container_images

  echo "Backup volumes ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific volumes"
  read -r backup_volumes

  echo "Backup networks ? (y/n/s)"
  echo "  y = yes (all), n = no, s = select specific networks"
  read -r backup_networks

  echo "Should I compress the backup directory ? (y/n)"
  read -r compress_backup
else
  backup_container_data="y"
  backup_container_images="y"
  backup_volumes="y"
  backup_networks="y"
  compress_backup="n"
fi

# Handle selective container data backup
if [ "$backup_container_data" = "s" ]
then
  if select_containers; then
    backup_container_data="y"
    export selected_containers
  else
    backup_container_data="n"
  fi
fi

# Handle selective image backup
if [ "$backup_container_images" = "s" ]
then
  if select_images; then
    backup_container_images="y"
    export selected_images
  else
    backup_container_images="n"
  fi
fi

# Handle selective volume backup
if [ "$backup_volumes" = "s" ]
then
  if select_volumes; then
    backup_volumes="y"
    export selected_volumes
  else
    backup_volumes="n"
  fi
fi

# Handle selective network backup
if [ "$backup_networks" = "s" ]
then
  if select_networks; then
    backup_networks="y"
    export selected_networks
  else
    backup_networks="n"
  fi
fi

if [ "$backup_container_data" = "y" ]
then
  source backup/backup-container-data.sh
fi

if [ "$backup_container_images" = "y" ]
then
  source backup/backup-images.sh
fi

if [ "$backup_volumes" = "y" ]
then
  source backup/backup-volumes.sh
fi

if [ "$backup_networks" = "y" ]
then
  source backup/backup-networks.sh
fi

if [ "$compress_backup" = "y" ]
then
  echo -n "Compressing backup directory - "
  tar -czf "$backup_path.tar.gz" "$backup_path" >/dev/null 2>&1
  echo "OK"

  echo -n "Removing backup directory - "
  rm -rf "$backup_path"
  echo "OK"
fi

echo ""
echo "Backup finished"

if [ "$compress_backup" = "y" ]
then
  echo "Backup file: $backup_path.tar.gz"
else
  echo "Backup directory: $backup_path"
fi

if [ "$docker_upload_enable" = true ]
then
  echo "- upload to dropbox"
  echo ""
  source backup/sync-dropbox.sh
  echo ""
fi
