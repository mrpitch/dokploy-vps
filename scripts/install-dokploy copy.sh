#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to read user input with validation
read_input() {
    local prompt="$1"
    local var_name="$2"
    local default_value="${3:-}"
    local required="${4:-true}"
    
    while true; do
        if [ -n "$default_value" ]; then
            read -p "$prompt [$default_value]: " input
            input="${input:-$default_value}"
        else
            read -p "$prompt: " input
        fi
        
        if [ "$required" = "true" ] && [ -z "$input" ]; then
            print_error "This field is required. Please enter a value."
            continue
        fi
        
        eval "$var_name='$input'"
        break
    done
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to validate SSH key file
validate_ssh_key() {
    local key_file="$1"
    if [ ! -f "$key_file" ]; then
        print_error "SSH key file not found: $key_file"
        return 1
    fi
    
    # Check if it's a valid private key
    if ! ssh-keygen -l -f "$key_file" >/dev/null 2>&1; then
        print_error "Invalid SSH private key file: $key_file"
        return 1
    fi
    
    return 0
}

# Function to setup SSH agent and add key
setup_ssh_agent() {
    local key_file="$1"
    local key_password="$2"
    
    print_info "Setting up SSH agent..."
    
    # Start ssh-agent
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    
    # Check if key is password protected
    if ssh-keygen -y -f "$key_file" >/dev/null 2>&1; then
        # Key is not password protected
        ssh-add "$key_file" 2>/dev/null
        return 0
    else
        # Key is password protected
        if [ -z "$key_password" ]; then
            print_error "SSH key is password protected but no password was provided."
            return 1
        fi
        
        # Try to add key with password using expect or sshpass
        if command_exists expect; then
            expect << EOF >/dev/null 2>&1
spawn ssh-add "$key_file"
expect "Enter passphrase"
send "$key_password\r"
expect eof
EOF
            return $?
        elif command_exists sshpass; then
            SSH_ASKPASS_REQUIRE=force sshpass -p "$key_password" ssh-add "$key_file" </dev/null 2>/dev/null
            return $?
        else
            print_warning "SSH key is password protected. Please enter password when prompted."
            ssh-add "$key_file"
            return $?
        fi
    fi
}

# Function to execute remote command via SSH
ssh_execute() {
    local user="$1"
    local host="$2"
    local key_file="${3:-}"
    local command="$4"
    
    local ssh_cmd="ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10"
    
    # Only add -i flag if key_file is provided
    if [ -n "$key_file" ]; then
        ssh_cmd="$ssh_cmd -i \"$key_file\""
    fi
    
    ssh_cmd="$ssh_cmd \"${user}@${host}\" \"$command\""
    
    eval "$ssh_cmd" 2>&1
}

# Function to check if devops user exists
check_devops_user() {
    local user="$1"
    local host="$2"
    local key_file="$3"
    
    local result=$(ssh_execute "$user" "$host" "$key_file" "id -u devops 2>/dev/null")
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        return 0
    else
        return 1
    fi
}

# Function to configure VPS
configure_vps() {
    local root_user="$1"
    local host="$2"
    local key_file="$3"
    local devops_username="devops"
    
    print_info "Starting VPS configuration..."
    
    # Step 1: Update system
    print_info "Updating system packages..."
    ssh_execute "$root_user" "$host" "$key_file" "
        export DEBIAN_FRONTEND=noninteractive
        apt update && apt upgrade -y && apt install -y curl wget git ufw fail2ban
    " || {
        print_error "Failed to update system packages"
        return 1
    }
    print_success "System packages updated"
    
    # Step 2: Create devops user
    print_info "Creating devops user..."
    ssh_execute "$root_user" "$host" "$key_file" "
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
    ssh_execute "$root_user" "$host" "$key_file" "
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
        echo "  ssh-copy-id -i $key_file $devops_username@$host"
        echo ""
        return 1
    }
    
    # Verify the key was copied correctly
    print_info "Verifying SSH key was copied correctly..."
    local key_check=$(ssh_execute "$root_user" "$host" "$key_file" "
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
        echo "  ssh-copy-id -i $key_file $devops_username@$host"
        echo ""
        read -p "Continue anyway? (y/N): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Verify devops user setup
    print_info "Verifying devops user setup..."
    ssh_execute "$root_user" "$host" "$key_file" "
        if groups $devops_username | grep -q sudo; then
            echo 'SUDO_OK'
        else
            echo 'SUDO_MISSING'
        fi
    " | grep -q "SUDO_OK" || {
        print_error "Devops user is not in sudo group. Attempting to fix..."
        ssh_execute "$root_user" "$host" "$key_file" "usermod -aG sudo $devops_username"
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
    if ssh_execute "$devops_username" "$host" "$key_file" "whoami" >/dev/null 2>&1; then
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
        echo "  ssh $devops_username@$host"
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
    
    # Step 5: Apply security measures (now that devops user is verified)
    echo ""
    print_info "Applying security measures..."
    print_warning "This will disable root SSH access and enable other security features."
    read -p "Continue with applying security measures? (Y/n): " apply_security
    apply_security="${apply_security:-Y}"
    
    if [[ ! "$apply_security" =~ ^[Yy]$ ]]; then
        print_info "Skipping security measures. You can apply them later manually."
        return 0
    fi
    
    # Step 5.1: Configure firewall
    print_info "Configuring firewall..."
    ssh_execute "$root_user" "$host" "$key_file" "
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
    
    # Step 5.2: Secure SSH configuration
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
    ssh_execute "$root_user" "$host" "$key_file" "
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    " || {
        print_error "Failed to backup SSH configuration"
        return 1
    }
    
    # Apply configuration changes based on user choices
    if [[ "$disable_root_login" =~ ^[Yy]$ ]]; then
        ssh_execute "$root_user" "$host" "$key_file" "
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
        ssh_execute "$root_user" "$host" "$key_file" "
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
    ssh_execute "$root_user" "$host" "$key_file" "
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
    
    # Step 5.3: Configure Fail2ban
    print_info "Configuring Fail2ban..."
    ssh_execute "$root_user" "$host" "$key_file" "
        systemctl enable fail2ban
        systemctl start fail2ban
    " || {
        print_warning "Failed to configure Fail2ban (non-critical)"
    }
    print_success "Fail2ban configured"
    
    # Step 5.4: Setup automatic security updates
    print_info "Setting up automatic security updates..."
    ssh_execute "$root_user" "$host" "$key_file" "
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

# Function to install Dokploy
install_dokploy() {
    local user="$1"
    local host="$2"
    local key_file="$3"
    
    print_info "Installing Dokploy..."
    
    # Check if ports are available
    print_info "Checking port availability..."
    local port_check=$(ssh_execute "$user" "$host" "$key_file" "
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
    ssh_execute "$user" "$host" "$key_file" "
        curl -sSL https://dokploy.com/install.sh | sudo sh
    " || {
        print_error "Failed to install Dokploy"
        return 1
    }
    
    print_success "Dokploy installation completed!"
    print_info "You can now access Dokploy at: http://$host:3000"
    return 0
}

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
    
    if ! command_exists curl; then
        print_error "curl is not installed. Please install it first."
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
    
    read_input "Domain name (optional, press Enter to skip)" "DOMAIN" "" "false"
    
    read_input "SSH key file path" "SSH_KEY_FILE" "$HOME/.ssh/id_ed25519" "true"
    SSH_KEY_FILE=$(eval echo "$SSH_KEY_FILE") # Expand ~ and variables
    
    if ! validate_ssh_key "$SSH_KEY_FILE"; then
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
    print_info "Testing SSH connection..."
    if ! ssh_execute "$SSH_USER" "$SERVER_IP" "" "whoami" >/dev/null 2>&1; then
        print_error "Cannot connect to server as user '$SSH_USER'. Please check:"
        echo "  - IP address is correct"
        echo "  - SSH key file is correct"
        echo "  - SSH key password (if protected)"
        echo "  - User '$SSH_USER' exists on the server"
        echo "  - SSH key is configured for user '$SSH_USER'"
        echo "  - Server is accessible"
        exit 1
    fi
    print_success "SSH connection successful as user '$SSH_USER'"
    
    # Ask if configuration should be applied
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
            if ! configure_vps "$SSH_USER" "$SERVER_IP" "$SSH_KEY_FILE"; then
                print_error "Server configuration failed"
                exit 1
            fi
            
            # Switch to devops user for remaining operations
            SSH_USER="devops"
            print_info "Switching to devops user for Dokploy installation..."
            
            # Test connection as devops user (using keys from agent)
            # Since we verified the devops user works before disabling root, this should succeed
            print_info "Testing connection as devops user..."
            if ! ssh_execute "$SSH_USER" "$SERVER_IP" "" "whoami" >/dev/null 2>&1; then
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
