#!/bin/bash

# Import common functions
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# Function to install Dokploy
install_dokploy() {
    local ssh_user="$1"
    local server_ip="$2"
    local ssh_key_file="$3"

    # check if dokploy is already installed
    local dokploy_installed=$(ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        sudo systemctl status dokploy | grep 'active (running)' || echo 'not_installed'
    ")
    if [ "$dokploy_installed" != "not_installed" ]; then
        print_warning "Dokploy is already installed"
        return 0
    fi
    
    print_info "Installing Dokploy..."
    
    # Check if ports are available
    print_info "Checking port availability..."
    local port_check=$(ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        sudo ss -tulnp | grep -E ':(80|443|3000) ' || echo 'ports_available'
    ")
    
    if echo "$port_check" | grep -qE ':(80|443|3000)'; then
        print_warning "One or more required ports (80, 443, 3000) are already in use."
        read -p "Continue anyway? (y/N): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            print_error "Installation cancelled"
            return 1
        fi
    fi
    
    # Run official Dokploy installation script
    print_info "Running official Dokploy installation script..."
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        curl -sSL https://dokploy.com/install.sh | sudo sh
    " || {
        print_error "Failed to install Dokploy"
        return 1
    }
    
    print_success "Dokploy installation completed!"
    print_info "You can now access Dokploy at: http://$server_ip:3000"
    return 0
}