#!/bin/bash
# Update sync_app to latest version by rebuilding the Docker image
# Run with: sudo ./update-sync-app.sh

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo:"
    echo "sudo ./update-sync-app.sh"
    exit 1
fi

echo "========================================="
echo "Updating sync_app to latest version"
echo "========================================="
echo ""
echo "NOTE: This will rebuild the Docker image with the latest sync_app code."
echo "This process takes about 10-15 minutes."
echo ""
read -p "Do you want to continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    exit 0
fi

cd /opt/frappe_docker

echo ""
echo "Step 1: Rebuilding Docker image with latest sync_app..."
export APPS_JSON_BASE64=$(base64 -w 0 apps.json)

docker build \
  --no-cache \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-15 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  --tag custom-erpnext:latest \
  --file images/custom/Containerfile .

if [ $? -ne 0 ]; then
    echo "ERROR: Docker build failed"
    exit 1
fi

echo ""
echo "Step 2: Restarting containers with new image..."
docker compose -f pwd.yml down
docker compose -f pwd.yml up -d

echo ""
echo "Step 3: Waiting for services to start..."
sleep 15

# Wait for backend
for i in {1..30}; do
    if docker ps --filter "name=frappe_docker-backend-1" --filter "status=running" | grep -q backend; then
        echo "Backend is running"
        break
    fi
    sleep 1
done

# Wait for websocket
for i in {1..30}; do
    if docker ps --filter "name=frappe_docker-websocket-1" --filter "status=running" | grep -q websocket; then
        echo "Websocket is running"
        break
    fi
    sleep 1
done

# Restart frontend
echo "Restarting frontend..."
docker restart frappe_docker-frontend-1

sleep 5

echo ""
echo "Step 4: Running migrations..."
docker compose -f pwd.yml exec backend bench --site erpnext.localhost migrate

echo ""
echo "Step 5: Clearing cache..."
docker compose -f pwd.yml exec backend bench --site erpnext.localhost clear-cache

echo ""
echo "Step 6: Restarting bench..."
docker compose -f pwd.yml exec backend bench restart

echo ""
echo "========================================="
echo "✓ sync_app updated successfully!"
echo "========================================="
echo ""
echo "Access ERPNext at: http://localhost:8080"
