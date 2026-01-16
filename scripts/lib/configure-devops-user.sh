#!/bin/bash

# Import common functions
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
    source "${SCRIPT_DIR}/lib/common.sh"
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

configure_devops_user() {
    local ssh_user="$1"
    local server_ip="$2"
    local ssh_key_file="$3"
    local devops_username="devops"

    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        if ! id -u $devops_username >/dev/null 2>&1; then
            adduser --disabled-password --gecos '' $devops_username
            usermod -aG sudo $devops_username
            echo '$devops_username ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/$devops_username
        fi
    " || {
        print_error "Failed to create devops user"
        return 1
    }
    print_success "Devops user created"
    
    # Step 3: Setup SSH key for devops user
    print_info "Setting up SSH key for devops user..."
    print_info "Copying SSH key from root's authorized_keys (added by Hetzner during server creation)..."
    
    # Copy the public key from root's authorized_keys to devops user's authorized_keys
    # This is more reliable since Hetzner already added the key to root during server creation
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        mkdir -p /home/$devops_username/.ssh
        if [ -f /root/.ssh/authorized_keys ]; then
            cp /root/.ssh/authorized_keys /home/$devops_username/.ssh/authorized_keys
        elif [ -f ~/.ssh/authorized_keys ]; then
            cp ~/.ssh/authorized_keys /home/$devops_username/.ssh/authorized_keys
        else
            echo 'ERROR: No authorized_keys found for root user'
            exit 1
        fi
        chmod 700 /home/$devops_username/.ssh
        chmod 600 /home/$devops_username/.ssh/authorized_keys
        chown -R $devops_username:$devops_username /home/$devops_username/.ssh
    " || {
        print_error "Failed to copy SSH key from root to devops user"
        print_warning "The SSH key might not have been added during Hetzner server creation."
        print_info "You can manually add your public key:"
        echo ""
        echo "  From your local machine:"
        echo "  ssh-copy-id -i $ssh_key_file $devops_username@$server_ip"
        echo ""
        return 1
    }

    # Verify the key was copied correctly
    print_info "Verifying SSH key was copied correctly..."
    local key_check=$(ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        if [ -f /home/$devops_username/.ssh/authorized_keys ] && [ -s /home/$devops_username/.ssh/authorized_keys ]; then
            if grep -q 'ssh-' /home/$devops_username/.ssh/authorized_keys; then
                echo 'KEY_VALID'
            else
                echo 'KEY_INVALID'
            fi
        else
            echo 'KEY_MISSING'
        fi
    ")
    
    if echo "$key_check" | grep -q "KEY_VALID"; then
        print_success "SSH key copied and verified successfully"
    else
        print_error "SSH key verification failed. The key may not have been copied correctly."
        print_warning "You may need to manually add your public key:"
        echo ""
        echo "  From your local machine:"
        echo "  ssh-copy-id -i $ssh_key_file $devops_username@$server_ip"
        echo ""
        read -p "Continue anyway? (y/N): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    # Verify devops user setup
    print_info "Verifying devops user setup..."
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        if groups $devops_username | grep -q sudo; then
            echo 'SUDO_OK'
        else
            echo 'SUDO_MISSING'
        fi
    " | grep -q "SUDO_OK" || {
        print_error "Devops user is not in sudo group. Attempting to fix..."
        ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "usermod -aG sudo $devops_username"
    }
    print_success "Devops user is in sudo group"
    
    # Step 4: Test devops user connection BEFORE disabling root
    echo ""
    print_warning "IMPORTANT: Before disabling root SSH access, we need to verify the devops user can connect."
    print_info "The devops user has been created with:"
    echo "  - Username: $devops_username"
    echo "  - SSH key configured"
    echo "  - Added to sudo group (with NOPASSWD privileges)"
    echo ""
    
    # Try to test connection programmatically first
    print_info "Testing devops user connection programmatically..."
    if ssh_execute "$devops_username" "$server_ip" "$ssh_key_file" "whoami" >/dev/null 2>&1; then
        print_success "Devops user connection test successful!"
        DEVOPS_CONNECTION_VERIFIED=true
    else
        print_warning "Automatic connection test failed. This might be due to:"
        echo "  - SSH key not yet recognized by the server"
        echo "  - SSH service needs to refresh"
        echo "  - Network/key propagation delay"
        echo ""
        print_info "Please test the devops user connection manually in another terminal:"
        echo ""
        echo "  ssh -i $ssh_key_file $devops_username@$server_ip"
        echo ""
        print_warning "After successfully connecting as devops user, verify:"
        echo "  1. You can connect without password (using SSH key)"
        echo "  2. You can run 'sudo whoami' and it returns 'root'"
        echo "  3. You can run 'sudo -v' without being prompted for password"
        echo ""
        read -p "Have you successfully tested the devops user connection? (y/N): " devops_tested
        if [[ ! "$devops_tested" =~ ^[Yy]$ ]]; then
            print_error "Please test the devops user connection first before continuing."
            print_info "Password authentication will remain enabled as a fallback."
            print_info "You can run this script again after verifying the devops user works."
            return 1
        fi
        DEVOPS_CONNECTION_VERIFIED=true
    fi
}