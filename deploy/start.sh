#!/bin/sh
#
# Start Script for steam-engine
# Builds and starts Docker containers
#

set -e

echo "Starting steam-engine..."

# Ensure clean state before starting
echo "Cleaning up any existing containers..."
docker compose down 2>/dev/null || true

# Build and start
echo "Building Docker image..."
docker compose build

echo "Starting containers..."
docker compose up -d

echo "Waiting for service to start..."
sleep 10

echo "Containers started."
docker compose ps
