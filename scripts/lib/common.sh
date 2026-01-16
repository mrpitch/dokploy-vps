#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    local ssh_user="$1"
    local server_ip="$2"
    local ssh_key_file="${3:-}"
    local command="$4"
    
    print_info "ssh_user: $ssh_user"
    print_info "server_ip: $server_ip"
    print_info "ssh_key_file: $ssh_key_file"
    print_info "command: $command"

    local ssh_cmd="ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10"
    
    # Prefer SSH agent if available, otherwise use key file
    if [ -n "$SSH_AUTH_SOCK" ] && ssh-add -l >/dev/null 2>&1; then
        print_info "SSH agent is running and has keys - use it (no -i flag needed)"
        :
    elif [ -n "$ssh_key_file" ]; then
        print_info "No agent available, use key file"
        ssh_cmd="$ssh_cmd -i \"$ssh_key_file\""
    fi
    
    ssh_cmd="$ssh_cmd \"${ssh_user}@${server_ip}\" \"$command\""
    
    eval "$ssh_cmd" 2>&1
}

# Function to restart system services
restart_system_services() {
    local ssh_user="$1"
    local server_ip="$2"
    local ssh_key_file="$3"
    
    print_info "Restarting system services..."
    ssh_execute "$ssh_user" "$server_ip" "$ssh_key_file" "
        sudo systemctl restart systemd-sysctl.service
        sudo systemctl restart systemd-sysctl.service
    " || {
        print_error "Failed to restart system services"
        return 1
    }
    print_success "System services restarted"
}

