#!/bin/bash

echo "Restoring container images"
echo "--------------------------"

# Find all container backup directories
for container_dir in "$backup_path"/*
do
    if [ -d "$container_dir" ]; then
        container_name=$(basename "$container_dir")
        image_file="$container_dir/$container_name-image.tar"
        
        if [ -f "$image_file" ]; then
            echo -n "$container_name - "
            docker load -i "$image_file" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
            fi
        fi
    fi
done

echo ""