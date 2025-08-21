#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Step 1: Install Nomad if not installed
install_nomad() {
    if ! command -v nomad &> /dev/null; then
        print_message $YELLOW "Installing Nomad..."
        
        # Download and install Nomad
        curl -fsSL -o nomad.zip https://releases.hashicorp.com/nomad/1.8.3/nomad_1.8.3_linux_amd64.zip
        unzip nomad.zip
        sudo mv nomad /usr/local/bin/
        rm nomad.zip
        
        print_message $GREEN "✅ Nomad installed successfully"
    else
        print_message $GREEN "✅ Nomad is already installed"
    fi
    
    nomad version
}

# Step 2: Create Nomad configuration
create_nomad_config() {
    print_message $YELLOW "Creating Nomad configuration..."
    
    sudo mkdir -p /etc/nomad.d
    sudo mkdir -p /var/lib/nomad
    
    # Create server configuration
    sudo tee /etc/nomad.d/nomad.hcl > /dev/null <<EOF
datacenter = "dc1"
data_dir = "/var/lib/nomad"
log_level = "INFO"
node_name = "nomad-server-1"

bind_addr = "0.0.0.0"

server {
  enabled = true
  bootstrap_expect = 1
}

client {
  enabled = true
  
  # Enable Docker driver
  options = {
    "driver.allowlist" = "docker,exec"
  }
}

consul {
  address = "127.0.0.1:8500"
}

acl = {
  enabled = true
}

ui_config {
  enabled = true
}

ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}
EOF

    print_message $GREEN "✅ Nomad configuration created"
}

# Step 3: Create systemd service
create_systemd_service() {
    print_message $YELLOW "Creating systemd service..."
    
    sudo tee /etc/systemd/system/nomad.service > /dev/null <<EOF
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/nomad.d/nomad.hcl

[Service]
Type=notify
User=nomad
Group=nomad
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/nomad.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # Create nomad user
    sudo useradd --system --home /var/lib/nomad --shell /bin/false nomad || true
    sudo chown -R nomad:nomad /var/lib/nomad
    sudo chown -R nomad:nomad /etc/nomad.d
    
    print_message $GREEN "✅ Systemd service created"
}

# Step 4: Start Nomad service
start_nomad() {
    print_message $YELLOW "Starting Nomad service..."
    
    sudo systemctl daemon-reload
    sudo systemctl enable nomad
    sudo systemctl start nomad
    
    # Wait for Nomad to be ready
    sleep 10
    
    if sudo systemctl is-active --quiet nomad; then
        print_message $GREEN "✅ Nomad service is running"
    else
        print_message $RED "❌ Failed to start Nomad service"
        sudo systemctl status nomad
        exit 1
    fi
}

# Step 5: Bootstrap ACL and get token
bootstrap_acl() {
    print_message $YELLOW "Bootstrapping ACL system..."
    
    # Set Nomad address
    export NOMAD_ADDR="http://127.0.0.1:4646"
    
    # Wait for Nomad to be ready
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if nomad node status &>/dev/null; then
            break
        fi
        print_message $YELLOW "Waiting for Nomad to be ready... ($((attempt + 1))/$max_attempts)"
        sleep 5
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        print_message $RED "❌ Nomad is not responding"
        exit 1
    fi
    
    # Bootstrap ACL
    local bootstrap_output
    if bootstrap_output=$(nomad acl bootstrap 2>/dev/null); then
        local secret_id=$(echo "$bootstrap_output" | grep "Secret ID" | awk '{print $4}')
        
        print_message $GREEN "✅ ACL bootstrapped successfully"
        print_message $GREEN "🔑 Management Token: $secret_id"
        
        # Save token to file (secure it!)
        echo "$secret_id" | sudo tee /etc/nomad.d/management.token > /dev/null
        sudo chmod 600 /etc/nomad.d/management.token
        sudo chown nomad:nomad /etc/nomad.d/management.token
        
        print_message $YELLOW "Token saved to /etc/nomad.d/management.token"
        print_message $YELLOW "Make sure to add this token to your GitHub secrets as NOMAD_TOKEN"
        
    else
        print_message $YELLOW "⚠️ ACL might already be bootstrapped"
        print_message $YELLOW "Check existing tokens with: nomad acl token list"
    fi
}

# Step 6: Setup firewall rules
setup_firewall() {
    print_message $YELLOW "Setting up firewall rules..."
    
    if command -v ufw &> /dev/null; then
        sudo ufw allow 4646/tcp  # Nomad HTTP
        sudo ufw allow 4647/tcp  # Nomad RPC
        sudo ufw allow 4648/tcp  # Nomad Serf
        print_message $GREEN "✅ UFW rules added"
    else
        print_message $YELLOW "⚠️ UFW not found, please configure firewall manually"
        print_message $YELLOW "Required ports: 4646 (HTTP), 4647 (RPC), 4648 (Serf)"
    fi
}

# Step 7: Show connection info
show_connection_info() {
    local droplet_ip=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address || echo "YOUR_DROPLET_IP")
    
    print_message $GREEN "🎉 Nomad setup completed!"
    print_message $YELLOW "Connection Information:"
    echo "  • Internal Address: http://127.0.0.1:4646"
    echo "  • External Address: http://${droplet_ip}:4646"
    echo "  • UI: http://${droplet_ip}:4646/ui"
    echo ""
    print_message $YELLOW "GitHub Actions Secrets:"
    echo "  • NOMAD_ADDR: http://${droplet_ip}:4646"
    echo "  • NOMAD_TOKEN: (check /etc/nomad.d/management.token)"
    echo ""
    print_message $YELLOW "Useful Commands:"
    echo "  • Check status: sudo systemctl status nomad"
    echo "  • View logs: sudo journalctl -u nomad -f"
    echo "  • Node status: nomad node status"
    echo "  • Job status: nomad job status"
}

# Main execution
main() {
    print_message $GREEN "🚀 Starting Nomad Production Setup"
    
    install_nomad
    create_nomad_config
    create_systemd_service
    start_nomad
    bootstrap_acl
    setup_firewall
    show_connection_info
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_message $RED "❌ This script must be run as root (use sudo)"
    exit 1
fi

main "$@"
