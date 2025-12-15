#!/bin/bash
# ====================================================
# ERPNext + Webshop Custom Builder (Docker Edition)
# Ubuntu Native Installation Script
# ====================================================
# Run with sudo

set -e

# ---------- CONFIG ----------
ERPNEXT_PORT=8080
INSTALL_DIR="/opt/frappe_docker"

# ---------- APPS RECIPE ----------
APPS_JSON='[
  {"name":"payments","url":"https://github.com/frappe/payments","branch":"version-15"},
  {"name":"erpnext","url":"https://github.com/frappe/erpnext","branch":"version-15"},
  {"name":"webshop","url":"https://github.com/frappe/webshop","branch":"version-15"},
  {"name":"sync_app","url":"https://github.com/Thebored1/erpnext_sync_app","branch":"main"}
]'

# ---------- HELPER FUNCTIONS ----------
print_step() {
    echo -e "\n\033[1;36m---> $1\033[0m"
}

print_success() {
    echo -e "\033[1;32m[OK] $1\033[0m"
}

print_error() {
    echo -e "\033[1;31m[ERROR] $1\033[0m"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root or with sudo"
    exit 1
fi

# ---------- 1. CLEANUP & FRESH INSTALL ----------
print_step "Cleaning up previous installations..."

# Stop and remove all Docker containers related to frappe/erpnext
if command -v docker &> /dev/null; then
    echo "Stopping and removing existing Docker containers..."
    
    # Stop all containers with frappe/erpnext in name or image
    docker ps -a --filter "name=frappe" -q | xargs -r docker stop 2>/dev/null || true
    docker ps -a --filter "name=erpnext" -q | xargs -r docker stop 2>/dev/null || true
    docker ps -a --filter "ancestor=custom-erpnext" -q | xargs -r docker stop 2>/dev/null || true
    
    # Remove containers
    docker ps -a --filter "name=frappe" -q | xargs -r docker rm -f 2>/dev/null || true
    docker ps -a --filter "name=erpnext" -q | xargs -r docker rm -f 2>/dev/null || true
    docker ps -a --filter "ancestor=custom-erpnext" -q | xargs -r docker rm -f 2>/dev/null || true
    
    # Remove custom erpnext images (all tags)
    docker images | grep "custom-erpnext" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
    
    # Remove frappe/erpnext images
    docker images | grep "frappe/erpnext" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
    
    # Clean up docker volumes related to frappe
    docker volume ls --filter "name=frappe" -q | xargs -r docker volume rm -f 2>/dev/null || true
    docker volume ls | grep "frappe_docker" | awk '{print $2}' | xargs -r docker volume rm -f 2>/dev/null || true
    
    # Remove Docker networks created by frappe_docker
    docker network ls --filter "name=frappe" -q | xargs -r docker network rm 2>/dev/null || true
    
    # Clean up dangling images and volumes
    echo "Cleaning up dangling Docker resources..."
    docker image prune -f 2>/dev/null || true
    docker volume prune -f 2>/dev/null || true
    
    # Clean up build cache to ensure fresh build
    echo "Cleaning Docker build cache..."
    docker builder prune -af 2>/dev/null || true
fi

# Remove installation directory and any related directories
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing previous installation directory: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
fi

# Remove any frappe-related data directories in common locations
echo "Checking for other frappe-related directories..."
rm -rf /home/*/frappe-bench 2>/dev/null || true
rm -rf /opt/frappe 2>/dev/null || true
rm -rf /var/lib/frappe 2>/dev/null || true

# Clean up any leftover Docker configurations (will be recreated)
rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
rm -f /etc/apt/keyrings/docker.gpg 2>/dev/null || true

# Clean up any temporary files from previous runs
rm -f /tmp/dockerd.log 2>/dev/null || true
rm -f /tmp/socat.log 2>/dev/null || true
rm -f /tmp/install_script.sh 2>/dev/null || true

print_success "Cleanup complete - all previous installations removed"

# ---------- 2. INSTALLING SYSTEM DEPENDENCIES ----------
print_step "Installing System Dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y socat git wget curl tar ca-certificates apt-transport-https gnupg lsb-release

print_success "System dependencies installed"

# ---------- 3. INSTALLING DOCKER ENGINE ----------
print_step "Installing Docker Engine..."

# Create keyrings directory
mkdir -p /etc/apt/keyrings

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

print_success "Docker installed"

# ---------- 4. STARTING DOCKER SERVICE ----------
print_step "Starting Docker Service..."

# Enable and start Docker service
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
for i in {1..30}; do
    if docker info > /dev/null 2>&1; then
        echo "Docker is running"
        break
    fi
    echo -n '.'
    sleep 1
done

if ! docker info > /dev/null 2>&1; then
    print_error "Docker failed to start"
    exit 1
fi

print_success "Docker is running"

# ---------- 5. SETTING UP FRAPPE DOCKER ----------
print_step "Setting up Frappe Docker repository..."

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Clone frappe_docker repository
git clone https://github.com/frappe/frappe_docker.git .

print_success "Frappe Docker repository cloned"

# ---------- 6. CREATING APPS RECIPE ----------
print_step "Creating apps.json recipe..."

echo "$APPS_JSON" > apps.json
echo "Apps configuration:"
cat apps.json

print_success "apps.json created"

# ---------- 7. BUILDING CUSTOM IMAGE ----------
print_step "Building custom ERPNext image..."
echo "This will take 10-15 minutes. Please be patient..."

export APPS_JSON_BASE64=$(base64 -w 0 apps.json)

docker build \
  --no-cache \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-15 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  --tag custom-erpnext:latest \
  --file images/custom/Containerfile .

print_success "Custom image built: custom-erpnext:latest"

# ---------- 8. CONFIGURING PWD.YML ----------
print_step "Configuring deployment file (pwd.yml)..."

# Update pwd.yml to use custom image and install all apps
sed -i 's|image: frappe/erpnext:v15.*|image: custom-erpnext:latest|g' pwd.yml
sed -i 's|--set-default frontend|--set-default erpnext.localhost|g' pwd.yml
sed -i 's|FRAPPE_SITE_NAME_HEADER: frontend|FRAPPE_SITE_NAME_HEADER: erpnext.localhost|g' pwd.yml
sed -i 's|--install-app erpnext|--install-app erpnext --install-app payments --install-app webshop --install-app sync_app|g' pwd.yml

print_success "Configuration updated"

# ---------- 9. STARTING THE SYSTEM ----------
print_step "Starting ERPNext containers..."

# Stop any existing containers
docker compose -f pwd.yml down 2>/dev/null || true

# Start the containers
docker compose -f pwd.yml up -d

print_success "Containers started"

# ---------- 10. WAITING FOR SERVICES ----------
print_step "Waiting for services to initialize..."
sleep 15

# Restart bench to ensure all apps are loaded
echo "Restarting bench..."
docker compose -f pwd.yml exec backend bench restart

print_success "Bench restarted"

# ---------- 11. FINAL STEPS ----------
print_step "Installation complete!"

echo ""
echo "========================================"
echo "CUSTOM DOCKER BUILD COMPLETE"
echo "========================================"
echo "Apps installed:"
echo "  - ERPNext"
echo "  - Payments"
echo "  - Webshop"
echo "  - Sync App"
echo ""
echo "Installation location: $INSTALL_DIR"
echo ""
echo "Access ERPNext at: http://localhost:$ERPNEXT_PORT"
echo "Or: http://$(hostname -I | awk '{print $1}'):$ERPNEXT_PORT"
echo ""
echo "Default credentials:"
echo "  Username: Administrator"
echo "  Password: admin"
echo "========================================"
echo ""
echo "Useful commands:"
echo "  - View logs: cd $INSTALL_DIR && docker compose -f pwd.yml logs -f"
echo "  - Stop: cd $INSTALL_DIR && docker compose -f pwd.yml down"
echo "  - Start: cd $INSTALL_DIR && docker compose -f pwd.yml up -d"
echo "  - Restart bench: cd $INSTALL_DIR && docker compose -f pwd.yml exec backend bench restart"
echo "========================================"
