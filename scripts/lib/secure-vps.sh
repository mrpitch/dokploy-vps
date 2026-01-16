#!/bin/bash

# Import common functions
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

secure_vps() {
    local ssh_user="$1"
    local server_ip="$2"
    local ssh_key_file="$3"

    print_info "ssh_user: $ssh_user"
    print_info "server_ip: $server_ip"
    print_info "ssh_key_file: $ssh_key_file"

    print_warning "This will disable root SSH access and enable other security features."
    read -p "Continue with applying security measures? (Y/n): " apply_security
    apply_security="${apply_security:-Y}"
    
    if [[ ! "$apply_security" =~ ^[Yy]$ ]]; then
        print_info "Skipping security measures. You can apply them later manually."
        return 0
    fi
    
    # Configure firewall
    print_info "Configuring firewall..."
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow OpenSSH
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 3000/tcp
        ufw --force enable
    " || {
        print_error "Failed to configure firewall"
        return 1
    }
    print_success "Firewall configured"
    
    # Secure SSH configuration
    print_info "Securing SSH configuration..."
    echo ""
    print_warning "SSH security configuration options:"
    echo "  1. Disable root login (recommended) - prevents direct root SSH access"
    echo "  2. Disable password authentication (optional) - only allow SSH keys"
    echo ""
    print_info "Since devops user is verified, you can now safely disable root login."
    echo ""
    read -p "Disable root SSH login? (Y/n): " disable_root_login
    disable_root_login="${disable_root_login:-Y}"
    
    read -p "Disable password authentication? (y/N): " disable_password_auth
    disable_password_auth="${disable_password_auth:-N}"
    
    # Build SSH configuration changes
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    " || {
        print_error "Failed to backup SSH configuration"
        return 1
    }
    
    # Apply configuration changes based on user choices
    if [[ "$disable_root_login" =~ ^[Yy]$ ]]; then
        ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
            sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
            sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
            if ! grep -q 'PermitRootLogin no' /etc/ssh/sshd_config; then
                echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
            fi
        " || {
            print_error "Failed to disable root login"
            return 1
        }
    fi
    
    if [[ "$disable_password_auth" =~ ^[Yy]$ ]]; then
        ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
            sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
            sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
            if ! grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config; then
                echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
            fi
        " || {
            print_error "Failed to disable password authentication"
            return 1
        }
    fi
    
    # Apply other security settings (always)
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
        sed -i 's/MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
        sed -i 's/#PermitEmptyPasswords yes/PermitEmptyPasswords no/' /etc/ssh/sshd_config
        sed -i 's/PermitEmptyPasswords yes/PermitEmptyPasswords no/' /etc/ssh/sshd_config
        if ! grep -q 'MaxAuthTries 3' /etc/ssh/sshd_config; then
            echo 'MaxAuthTries 3' >> /etc/ssh/sshd_config
        fi
        if ! grep -q 'PermitEmptyPasswords no' /etc/ssh/sshd_config; then
            echo 'PermitEmptyPasswords no' >> /etc/ssh/sshd_config
        fi
        sshd -t && (systemctl restart ssh 2>/dev/null || systemctl restart sshd)
    " || {
        print_error "Failed to apply SSH security settings"
        return 1
    }
    
    # Report what was configured
    local config_summary="SSH configuration secured:"
    if [[ "$disable_root_login" =~ ^[Yy]$ ]]; then
        config_summary="$config_summary root login disabled;"
    else
        config_summary="$config_summary root login enabled;"
    fi
    if [[ "$disable_password_auth" =~ ^[Yy]$ ]]; then
        config_summary="$config_summary password authentication disabled"
    else
        config_summary="$config_summary password authentication enabled"
    fi
    print_success "$config_summary"
    
    # Configure Fail2ban
    print_info "Configuring Fail2ban..."
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        systemctl enable fail2ban
        systemctl start fail2ban
    " || {
        print_warning "Failed to configure Fail2ban (non-critical)"
    }
    print_success "Fail2ban configured"
    
    # Step 5.4: Setup automatic security updates
    print_info "Setting up automatic security updates..."
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        export DEBIAN_FRONTEND=noninteractive
        apt install -y unattended-upgrades
        echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
        dpkg-reconfigure -f noninteractive unattended-upgrades
    " || {
        print_warning "Failed to setup automatic security updates (non-critical)"
    }
    print_success "Automatic security updates configured"
    
    print_success "VPS configuration completed!"
    return 0
}

