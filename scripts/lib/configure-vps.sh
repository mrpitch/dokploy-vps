#!/bin/bash

# Import common functions
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# check if add-devops-user.sh exists
if [ -f "${SCRIPT_DIR}/lib/configure-devops-user.sh" ]; then
    source "${SCRIPT_DIR}/lib/configure-devops-user.sh"
else
    echo "Error: configure-devops-user.sh not found" >&2
    exit 1
fi

# check if secure-vps.sh exists
if [ -f "${SCRIPT_DIR}/lib/secure-vps.sh" ]; then
    source "${SCRIPT_DIR}/lib/secure-vps.sh"
else
    echo "Error: secure-vps.sh not found" >&2
    exit 1
fi
# Function to configure VPS
configure_vps() {
    local ssh_user="$1"
    local server_ip="$2"
    local ssh_key_file="$3"
    local server_timezone="$4"
    
    print_info "Starting VPS configuration..."

    # Step 1: Update system
    print_info "Updating system packages..."
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        export DEBIAN_FRONTEND=noninteractive
        apt update && apt upgrade -y && apt install -y curl wget git ufw fail2ban
        sudo timedatectl set-timezone $server_timezone
    " || {
        print_error "Failed to update system packages"
        return 1
    }
    print_success "System packages updated"

   # Step 2: Create devops user
    print_info "Creating devops user..."
    if ! configure_devops_user "$ssh_user" "$server_ip" "$ssh_key_file"; then
        print_error "Failed to create devops user"
        return 1
    fi

    # Step 3: Apply security measures (now that devops user is verified)
    echo ""
    print_info "Applying security measures..."
    if ! secure_vps "$ssh_user" "$server_ip" "$ssh_key_file"; then
        print_error "Failed to apply security measures"
        return 1
    fi
    print_success "Security measures applied"

    print_success "VPS configuration completed!"
    return 0
}