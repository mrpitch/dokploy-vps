#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Import common functions

# check if common.sh exists
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# check if configure-vps.sh exists
if [ -f "${SCRIPT_DIR}/lib/configure-vps.sh" ]; then
    source "${SCRIPT_DIR}/lib/configure-vps.sh"
else
    echo "Error: configure-vps.sh not found" >&2
    exit 1
fi

# check if install-dokploy.sh exists
if [ -f "${SCRIPT_DIR}/lib/install-dokploy.sh" ]; then
    source "${SCRIPT_DIR}/lib/install-dokploy.sh"
else
    echo "Error: install-dokploy.sh not found" >&2
    exit 1
fi

# Main script
main() {
    clear
    echo "=========================================="
    echo "  Dokploy VPS Installation Script"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    if ! command_exists ssh; then
        print_error "SSH is not installed. Please install it first."
        exit 1
    fi
    
    # Collect user input
    print_info "Please provide the following information:"
    echo ""
    
    read_input "Server IP address" "SERVER_IP" "" "true"
    if ! validate_ip "$SERVER_IP"; then
        print_error "Invalid IP address format"
        exit 1
    fi

    read_input "SSH key file path" "SSH_KEY_FILE" "~/.ssh/id_ed25519" "true"
    SSH_KEY_FILE=$(eval echo "$SSH_KEY_FILE") # Expand ~ and variables
    
    if ! validate_ssh_key "$SSH_KEY_FILE"; then
        print_error "Invalid SSH key file"
        exit 1
    fi

    read_input "Server timezone" "SERVER_TIMEZONE" "Europe/Berlin" "true"
    if ! validate_timezone "$SERVER_TIMEZONE"; then
        print_error "Invalid timezone format"
        exit 1
    fi

    # Ask for SSH key password (only once)
    read -sp "SSH key password (if protected, press Enter if not): " SSH_KEY_PASSWORD
    echo ""
    
    # Setup SSH agent
    print_info "Setting up SSH agent..."
    if ! setup_ssh_agent "$SSH_KEY_FILE" "$SSH_KEY_PASSWORD"; then
        print_warning "Could not add SSH key to agent. You may be prompted for password during execution."
    else
        print_success "SSH key added to agent"
    fi
    
    # Ask user which SSH user to use
    echo ""
    print_info "Which user do you want to use for SSH connection?"
    read -p "Use root user? (Y/n): " use_root
    use_root="${use_root:-Y}"
    
    if [[ "$use_root" =~ ^[Yy]$ ]]; then
        SSH_USER="root"
        CONFIG_APPLIED=false
        print_info "Using root user for SSH connection."
    else
        print_warning "If you're not using root, you need to have set up another user with sudo rights."
        print_info "This user should already exist on the server and have your SSH key configured."
        read_input "Enter SSH username" "SSH_USER" "devops" "true"
        CONFIG_APPLIED=true
        print_info "Using user '$SSH_USER' for SSH connection."
    fi

    # Test SSH connection (key is now in agent, so we don't need to pass key_file)
    print_info "Connecting to server as $SSH_USER..."
    ssh -i "$SSH_KEY_FILE" $SSH_USER@$SERVER_IP "whoami"
    if [ $? -ne 0 ]; then
        print_error "Cannot connect to server as user '$SSH_USER'. Please check:"
        echo "  - IP address is correct"
        echo "  - User '$SSH_USER' exists on the server"
        echo "  - SSH key is configured for user '$SSH_USER'"
        echo "  - Server is accessible"
        exit 1
    fi

    # Ask if server configuration should be applied
    if [ "$CONFIG_APPLIED" = "false" ]; then
        echo ""
        print_warning "Server configuration has not been applied yet."
        print_info "The script will now configure the server with:"
        echo "  - System updates"
        echo "  - Devops user creation"
        echo "  - SSH key setup"
        echo "  - Firewall configuration"
        echo "  - SSH security hardening"
        echo "  - Fail2ban setup"
        echo "  - Automatic security updates"
        echo ""
        print_warning "After configuration, you will need to use the 'devops' user for SSH connections."
        echo ""
        read -p "Do you want to apply the server configuration now? (Y/n): " apply_config
        apply_config="${apply_config:-Y}"
        
        if [[ "$apply_config" =~ ^[Yy]$ ]]; then
        # Configure VPS
            if ! configure_vps "$SSH_USER" "$SERVER_IP" "$SSH_KEY_FILE" "$SERVER_TIMEZONE"; then
                print_error "Server configuration failed"
                exit 1
            fi
            
             # Switch to devops user for remaining operations
            SSH_USER="devops"
            print_info "Switching to devops user for Dokploy installation..."
            
            # Test connection as devops user (using keys from agent)
            # Since we verified the devops user works before disabling root, this should succeed
            print_info "Testing connection as devops user..."
            if ! ssh_execute "$SSH_USER" "$SERVER_IP" "$SSH_KEY_FILE" "whoami" >/dev/null 2>&1; then
                print_error "Cannot connect as devops user."
                print_warning "This might happen if root SSH was disabled before devops user was fully configured."
                print_info "Please verify you can connect manually: ssh devops@$SERVER_IP"
                exit 1
            fi
            print_success "Successfully connected as devops user"
        else
            print_info "Skipping server configuration. Using current user: $SSH_USER"
        fi
    fi
    
       # add swap
    print_info "Adding swap..."
    ssh_execute "$SSH_USER" "$SERVER_IP" "$SSH_KEY_FILE" "
        # Check if swap already exists and is active
        if [ -f /swapfile ] && swapon --show | grep -q /swapfile; then
            echo 'Swap already configured and active'
            exit 0
        fi
        
        # Create swapfile if it doesn't exist
        if [ ! -f /swapfile ]; then
            sudo fallocate -l 8G /swapfile || exit 1
            sudo chmod 600 /swapfile || exit 1
            sudo mkswap /swapfile || exit 1
        fi
        
        # Enable swap if not already active
        if ! swapon --show | grep -q /swapfile; then
            sudo swapon /swapfile || exit 1
        fi
        
        # Add to fstab if not already there
        if ! grep -q '/swapfile none swap' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab || exit 1
        fi
        
        echo 'Swap configured successfully'
    " || {
        print_error "Failed to add swap"
        exit 1
    }
    print_success "Swap added"

    #restart system services
    print_info "Restarting system services..."
    

    # Install Dokploy
    echo ""
    print_info "Proceeding with Dokploy installation..."
    read -p "Continue with Dokploy installation? (Y/n): " install_dokploy
    install_dokploy="${install_dokploy:-Y}"
    
    if [[ "$install_dokploy" =~ ^[Yy]$ ]]; then
        if ! install_dokploy "$SSH_USER" "$SERVER_IP" "$SSH_KEY_FILE"; then
            print_error "Dokploy installation failed"
            exit 1
        fi
        
        echo ""
        print_success "=========================================="
        print_success "  Installation Complete!"
        print_success "=========================================="
        echo ""
        print_info "Next steps:"
        echo "  1. Access Dokploy dashboard: http://$SERVER_IP:3000"
        if [ -n "$DOMAIN" ]; then
            echo "  2. Configure domain in Dokploy: $DOMAIN"
            echo "  3. Enable HTTPS/SSL in Dokploy settings"
        fi
        echo "  4. Create your admin account in the Dokploy dashboard"
        echo ""
    else
        print_info "Dokploy installation skipped"
    fi
    
}


# Run main function
main "$@"