#!/bin/bash

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

if [ "$non_interactive" = false ]
then
  echo "Restore container images ? (y/n)"
  read -r restore_images

  echo "Restore volumes ? (y/n)"
  read -r restore_volumes

  echo "Restore containers ? (y/n)"
  read -r restore_containers
else
  restore_images="y"
  restore_volumes="y"
  restore_containers="y"
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
echo "Restored images: $(docker images --format '{{.Repository}}:{{.Tag}}' | wc -l)"
echo "Restored volumes: $(docker volume ls -q | wc -l)"
echo "Running containers: $(docker ps --format '{{.Names}}' | wc -l)"