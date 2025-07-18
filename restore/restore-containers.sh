#!/bin/bash

echo "Restoring containers"
echo "-------------------"

# Find all container backup directories
for container_dir in "$backup_path"/*
do
    if [ -d "$container_dir" ]; then
        container_name=$(basename "$container_dir")
        data_file="$container_dir/$container_name-data.txt"

        if [ -f "$data_file" ]; then
            echo -n "$container_name - "

            # Check if container already exists
            if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
                echo "EXISTS (skipping)"
                continue
            fi

            # Read the container data file
            container_data=$(cat "$data_file")

            # Debug: Check if the JSON is valid
            if ! echo "$container_data" | jq empty >/dev/null 2>&1; then
                echo "WARNING: Invalid JSON detected, using fallback parsing"
                use_fallback=true
            else
                use_fallback=false
            fi

            # Extract the JSON object (handle both array format [{}] and object format {})
            if [ "$use_fallback" = false ]; then
                # Try to extract clean JSON
                if echo "$container_data" | jq -e 'type == "array"' >/dev/null 2>&1; then
                    container_json=$(echo "$container_data" | jq '.[0]')
                else
                    container_json="$container_data"
                fi
            fi

            if [ "$use_fallback" = false ] && echo "$container_json" | jq empty >/dev/null 2>&1; then
                # Use jq for reliable JSON parsing
                image=$(echo "$container_json" | jq -r '.Config.Image // empty' 2>/dev/null)

                # Environment variables
                env_vars=$(echo "$container_json" | jq -r '.Config.Env[]? // empty' 2>/dev/null | grep '=' | sed 's/^/-e "/' | sed 's/$/"/' | tr '\n' ' ')

                # Port mappings
                ports=$(echo "$container_json" | jq -r '
                    .HostConfig.PortBindings // {} |
                    to_entries[] |
                    select(.value and (.value | length > 0)) |
                    "-p " + (.value[0].HostPort // "0") + ":" + (.key | split("/")[0])
                ' 2>/dev/null | tr '\n' ' ')

                # Volume mounts
                volumes=$(echo "$container_json" | jq -r '
                    .Mounts[]? // [] |
                    select(.Source and .Destination) |
                    "-v \"" + .Source + "\":\"" + .Destination + "\""
                ' 2>/dev/null | tr '\n' ' ')

                # Working directory
                workdir=$(echo "$container_json" | jq -r '.Config.WorkingDir // empty' 2>/dev/null)
                if [ -n "$workdir" ] && [ "$workdir" != "" ] && [ "$workdir" != "null" ]; then
                    workdir="-w \"$workdir\""
                else
                    workdir=""
                fi

                # Restart policy
                restart_policy=$(echo "$container_json" | jq -r '.HostConfig.RestartPolicy.Name // "no"' 2>/dev/null)
                if [ -n "$restart_policy" ] && [ "$restart_policy" != "no" ] && [ "$restart_policy" != "null" ]; then
                    restart="--restart=$restart_policy"
                else
                    restart=""
                fi

                # Network mode
                network_mode=$(echo "$container_json" | jq -r '.HostConfig.NetworkMode // "default"' 2>/dev/null)
                if [ -n "$network_mode" ] && [ "$network_mode" != "default" ] && [ "$network_mode" != "null" ]; then
                    network="--network=$network_mode"
                else
                    network=""
                fi

                # Command (only if it exists and is not null)
                cmd=$(echo "$container_json" | jq -r '.Config.Cmd[]? // empty' 2>/dev/null | tr '\n' ' ')

            else
                # Fallback to grep/sed parsing for malformed JSON
                echo "Using fallback parsing for $container_name..."

                # Extract image more carefully
                image=$(echo "$container_data" | grep -o '"Image"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"Image"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

                # Extract environment variables more carefully
                env_section=$(echo "$container_data" | sed -n '/"Env"[[:space:]]*:[[:space:]]*\[/,/\]/p')
                env_vars=$(echo "$env_section" | grep '"[^"]*=[^"]*"' | sed 's/.*"\([^"]*=[^"]*\)".*/\1/' | sed 's/^/-e "/' | sed 's/$/"/' | tr '\n' ' ')

                # Extract basic port bindings
                port_section=$(echo "$container_data" | sed -n '/"PortBindings"[[:space:]]*:[[:space:]]*{/,/}/p')
                ports=$(echo "$port_section" | grep -o '"[0-9]*\/tcp"[[:space:]]*:[[:space:]]*\[[^]]*"HostPort"[[:space:]]*:[[:space:]]*"[0-9]*"' | sed 's/"[0-9]*\/tcp".*"HostPort"[[:space:]]*:[[:space:]]*"\([0-9]*\)"/\1/' | head -5 | while read -r host_port; do
                    container_port=$(echo "$port_section" | grep -B5 "\"HostPort\"[[:space:]]*:[[:space:]]*\"$host_port\"" | grep -o '"[0-9]*/tcp"' | sed 's/"//g' | sed 's|/tcp||')
                    if [ -n "$host_port" ] && [ -n "$container_port" ]; then
                        echo "-p $host_port:$container_port"
                    fi
                done | tr '\n' ' ')

                # Extract volume mounts
                mount_section=$(echo "$container_data" | sed -n '/"Mounts"[[:space:]]*:[[:space:]]*\[/,/\]/p')
                volumes=$(echo "$mount_section" | grep -A1 -B1 '"Source"' | grep -A1 '"Source"[[:space:]]*:[[:space:]]*"[^"]*"' | paste - - | sed 's/.*"Source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*"Destination"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1 \2/' | while read -r src dest; do
                    if [ -n "$src" ] && [ -n "$dest" ]; then
                        echo "-v \"$src\":\"$dest\""
                    fi
                done | tr '\n' ' ')

                # Extract working directory
                workdir=$(echo "$container_data" | grep -o '"WorkingDir"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"WorkingDir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
                if [ -n "$workdir" ] && [ "$workdir" != "" ]; then
                    workdir="-w \"$workdir\""
                else
                    workdir=""
                fi

                # Extract restart policy
                restart_policy=$(echo "$container_data" | grep -A5 '"RestartPolicy"' | grep '"Name"' | head -1 | sed 's/.*"Name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
                if [ -n "$restart_policy" ] && [ "$restart_policy" != "no" ]; then
                    restart="--restart=$restart_policy"
                else
                    restart=""
                fi

                # Extract network mode
                network_mode=$(echo "$container_data" | grep -o '"NetworkMode"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"NetworkMode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
                if [ -n "$network_mode" ] && [ "$network_mode" != "default" ]; then
                    network="--network=$network_mode"
                else
                    network=""
                fi

                # Extract command
                cmd_section=$(echo "$container_data" | sed -n '/"Cmd"[[:space:]]*:[[:space:]]*\[/,/\]/p')
                cmd=$(echo "$cmd_section" | grep '"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' | tr '\n' ' ')
            fi

            # Validate we have at least an image
            if [ -z "$image" ] || [ "$image" = "null" ]; then
                echo "FAILED (no image found)"
                continue
            fi

            # Clean up any empty values and extra spaces
            env_vars=$(echo "$env_vars" | sed 's/  */ /g' | sed 's/^ *//' | sed 's/ *$//')
            ports=$(echo "$ports" | sed 's/  */ /g' | sed 's/^ *//' | sed 's/ *$//')
            volumes=$(echo "$volumes" | sed 's/  */ /g' | sed 's/^ *//' | sed 's/ *$//')
            cmd=$(echo "$cmd" | sed 's/  */ /g' | sed 's/^ *//' | sed 's/ *$//')

            # Build and run the docker run command
            docker_cmd="docker run -d --name \"$container_name\""
            [ -n "$env_vars" ] && docker_cmd="$docker_cmd $env_vars"
            [ -n "$ports" ] && docker_cmd="$docker_cmd $ports"
            [ -n "$volumes" ] && docker_cmd="$docker_cmd $volumes"
            [ -n "$workdir" ] && docker_cmd="$docker_cmd $workdir"
            [ -n "$restart" ] && docker_cmd="$docker_cmd $restart"
            [ -n "$network" ] && docker_cmd="$docker_cmd $network"
            docker_cmd="$docker_cmd \"$image\""
            [ -n "$cmd" ] && docker_cmd="$docker_cmd $cmd"

            # Execute the command
            eval "$docker_cmd" >/dev/null 2>&1

            if [ $? -eq 0 ]; then
                echo "OK"
            else
                echo "FAILED"
                echo "Command: $docker_cmd"
            fi
        fi
    fi
done

echo ""
