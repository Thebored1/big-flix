#!/bin/bash
# Simple ERPNext Startup Script
# Run this with: sudo ./start-erpnext.sh

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo:"
    echo "sudo ./start-erpnext.sh"
    exit 1
fi

# Check if installation exists
if [ ! -d "/opt/frappe_docker" ]; then
    echo "ERROR: ERPNext not installed at /opt/frappe_docker"
    echo "Please run the installation script first:"
    echo "sudo ./install_custom_erpnext_docker.sh"
    exit 1
fi

cd /opt/frappe_docker

echo "Starting ERPNext containers..."
docker compose -f pwd.yml up -d

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start containers"
    echo "Check if Docker is running: systemctl status docker"
    exit 1
fi

echo "Waiting for backend and websocket services to be ready..."
sleep 10

# Wait for backend container to be running
echo "Checking backend container..."
for i in {1..30}; do
    if docker ps --filter "name=frappe_docker-backend-1" --filter "status=running" | grep -q backend; then
        echo "Backend is running"
        break
    fi
    sleep 1
done

# Wait for websocket container to be running
echo "Checking websocket container..."
for i in {1..30}; do
    if docker ps --filter "name=frappe_docker-websocket-1" --filter "status=running" | grep -q websocket; then
        echo "Websocket is running"
        break
    fi
    sleep 1
done

# Restart frontend container to ensure it can connect to backend
echo "Restarting frontend container..."
docker restart frappe_docker-frontend-1

# Wait a bit for frontend to start
sleep 5

# Check if frontend is running
if docker ps --filter "name=frappe_docker-frontend-1" --filter "status=running" | grep -q frontend; then
    echo "Frontend is running"
else
    echo "WARNING: Frontend container may still be starting..."
    echo "Check logs with: sudo docker logs frappe_docker-frontend-1"
fi

echo ""
echo "Restarting bench..."
docker compose -f pwd.yml exec backend bench restart

echo ""
echo "ERPNext started!"
echo "Access at: http://localhost:8080"
echo ""
echo "If you can't access it, wait 1-2 minutes and check container status:"
echo "  sudo docker ps"
