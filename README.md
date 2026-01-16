# Install dokploy on VPS

Dokploy is an open-source alternative to Heroku, Vercel, and Netlify, designed to simplify application deployment and management using Docker and Traefik.

This project provides a step-by-step guide and automation scripts for deploying [Dokploy](https://dokploy.com) on a Virtual Private Server (VPS). Dokploy is a self-hosted deployment platform that simplifies managing Docker containers and applications.

This guide covers everything from initial server setup and configuration to installing Dokploy, ensuring your VPS meets all the requirements for running Dokploy successfully. While this example uses Hetzner, the instructions can be adapted for any VPS provider.

**Favoravle VPS Provider**

- **Hetzner** - https://www.hetzner.com/
- **Hostinger** - https://www.hostinger.com/
- **RackNerd** - https://www.racknerd.com/

## Table of Contents

- [Create & configure VPS](#create--configure-vps)
  - [Create VPS](#create-vps)
  - [Optional: Creating an SSH Key](#optional-creating-an-ssh-key)
  - [Configure VPS](#configure-vps)
- [Install dokploy](#install-dokploy)
  - [Step 1: Verify Port Availability](#step-1-verify-port-availability)
  - [Step 2: Update System Packages](#step-2-update-system-packages)
  - [Step 3: Install Dokploy](#step-3-install-dokploy)
  - [Step 4: Configure Firewall](#step-4-configure-firewall)
  - [Step 5: Access Dokploy Dashboard](#step-5-access-dokploy-dashboard)
  - [Step 6: Configure Domain and SSL/TLS (Recommended for Production)](#step-6-configure-domain-and-ssltls-recommended-for-production)
  - [Step 7: Verify Installation](#step-7-verify-installation)
  - [Step 8: Post-Installation Configuration](#step-8-post-installation-configuration)
  - [Troubleshooting](#troubleshooting)
  - [Next Steps](#next-steps-1)
  - [Additional Resources](#additional-resources)
- [VPS Considerations](#vps-considerations)
  - [Scenario 1: Dokploy + Supabase + n8n + 1-3 Next.js Apps with PayloadCMS](#scenario-1-dokploy--supabase--n8n--1-3-nextjs-apps-with-payloadcms)
  - [Scenario 2: Dokploy + n8n + 1-3 Next.js Apps with PayloadCMS](#scenario-2-dokploy--n8n--1-3-nextjs-apps-with-payloadcms)
  - [Important Considerations for Both Scenarios](#important-considerations-for-both-scenarios)

## Create & configure VPS

### Create VPS

Before installing Dokploy, you need to create and configure a VPS server. This section provides guidance for setting up a server on Hetzner Cloud, but the general principles apply to other providers as well.

#### Quick Steps for Hetzner Cloud

1. **Sign up/Login**: Create an account at [Hetzner Cloud Console](https://console.hetzner.cloud/) if you haven't already.

2. **Create a New Project** (optional but recommended):
   - Click "Add Project" in the console
   - Give it a name (e.g., "Dokploy Production")

3. **Create a Server**:
   - Click "Add Server" in your project
   - Choose your preferred location (datacenter)
   - Select an image: **Ubuntu 22.04** or **Ubuntu 24.04** (recommended for Dokploy)
   - Choose server type: Minimum **2 vCPU, 4 GB RAM** (CPX11 or better)
   - Configure SSH keys (see [Creating an SSH Key](#optional-creating-an-ssh-key) section below)
   - Set a hostname (optional)
   - Click "Create & Buy Now"

4. **Important Configuration Notes**:
   - **Operating System**: Ubuntu 22.04 LTS or 24.04 LTS is recommended
   - **Resources**: Dokploy requires at least 2GB RAM and 2 vCPUs for optimal performance
   - **SSH Keys**: Add your public SSH key during server creation for secure access
   - **Firewall**: Consider setting up a firewall rule to allow SSH (port 22) and HTTP/HTTPS (ports 80, 443)

5. **Access Your Server**:
   - Once created, note your server's IP address
   - Connect via SSH: `ssh root@your-server-ip` (or `ssh your-username@your-server-ip`)

#### Official Documentation

For detailed instructions and video tutorials, please refer to:
- **Hetzner Official Docs**: [Creating a Server](https://docs.hetzner.com/cloud/servers/getting-started/creating-a-server/)
- Search YouTube for "Hetzner Cloud create server" for video walkthroughs

#### For Other VPS Providers

The general steps are similar across providers:
1. Create an account
2. Choose Ubuntu 22.04 or 24.04
3. Select appropriate server resources (2+ vCPU, 4+ GB RAM)
4. Configure SSH access
5. Deploy the server

### Optional: Creating an SSH Key

#### 1. Generate a new SSH key pair

**Recommended: Ed25519 (modern, secure)**
```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

**Alternative: RSA (if Ed25519 isn't supported)**
```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

#### 2. During key generation

- **File location**: Press Enter to use the default (`~/.ssh/id_ed25519` or `~/.ssh/id_rsa`), or specify a custom path.
- **Passphrase**: Optional but recommended. Adds a password to protect your private key.

#### 3. Add your SSH key to the ssh-agent

```bash
# Start the ssh-agent
eval "$(ssh-agent -s)"

# Add your SSH private key to the ssh-agent
ssh-add ~/.ssh/id_ed25519
# Or if you used RSA:
# ssh-add ~/.ssh/id_rsa
```

#### 4. Copy your public key to your VPS

**Option A: Using ssh-copy-id (easiest)**
```bash
ssh-copy-id user@your-server-ip
```

**Option B: Manual copy**
```bash
# Display your public key
cat ~/.ssh/id_ed25519.pub

# Then SSH into your server and add it to ~/.ssh/authorized_keys
ssh user@your-server-ip
mkdir -p ~/.ssh
echo "your-public-key-here" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

*TIP: ~ is done by Option (⌥) + N on German Mac keyboard*

#### 5. Test your SSH connection

```bash
ssh user@your-server-ip
```

**Note**: For Hetzner VPS, you can also add your public key in the Hetzner Cloud Console when creating the server, so it's automatically configured.

**Quick reference:**
- **Private key**: `~/.ssh/id_ed25519` (keep this secret, never share)
- **Public key**: `~/.ssh/id_ed25519.pub` (this is what you share/add to servers)

### Configure VPS

After creating your VPS, you need to configure it for secure and efficient operation. This guide covers initial server setup, user creation, and basic security hardening.

#### Step 1: Connect to Your Server as Root

First, connect to your server using SSH. If you added your SSH key during server creation, you can connect directly:

```bash
ssh root@your-server-ip
```

If you're using a password for root access, you'll be prompted to enter it. For security reasons, we'll disable password authentication later.

#### Step 2: Update the System

Once connected, update all system packages to their latest versions:

```bash
# Update package list
apt update

# Upgrade all installed packages
apt upgrade -y

# Install essential tools
apt install -y curl wget git ufw fail2ban
```

**Note**: The `-y` flag automatically confirms package installations. The upgrade may take a few minutes depending on the number of packages.

#### Step 3: Create a DevOps User

It's a security best practice to avoid using the root account for daily operations. Create a dedicated user for DevOps tasks:

```bash
# Create a new user (replace 'devops' with your preferred username)
adduser devops
```

You'll be prompted to:
- Set a password (choose a strong password)
- Enter full name (optional, press Enter to skip)
- Enter room number, work phone, etc. (optional, press Enter to skip)
- Confirm the information (type 'Y' and press Enter)

#### Step 4: Add User to Sudo Group

Grant your new user administrative privileges by adding them to the `sudo` group:

```bash
# Add user to sudo group
usermod -aG sudo devops

# Verify the user was added to sudo group
groups devops
```

You should see `sudo` in the output. This allows the user to run commands with administrative privileges using `sudo`.

#### Step 5: Set Up SSH Key for the New User

Copy your SSH public key to the new user's account for passwordless authentication:

```bash
# Create .ssh directory for the new user
mkdir -p /home/devops/.ssh

# Copy your public key (replace with your actual public key)
echo "your-public-key-here" > /home/devops/.ssh/authorized_keys

# Set proper permissions
chmod 700 /home/devops/.ssh
chmod 600 /home/devops/.ssh/authorized_keys
chown -R devops:devops /home/devops/.ssh
```

**Alternative**: If you're already connected via SSH with your key, you can copy from your local machine:

```bash
# From your local machine, run:
ssh-copy-id devops@your-server-ip
```

#### Step 6: Test the New User Account

Before disconnecting, test that the new user can use sudo:

```bash
# Switch to the new user
su - devops

# Test sudo access
sudo whoami
```

You should see `root` as the output. If prompted for a password, enter the password you set for the devops user.

#### Step 7: Basic Security Hardening

Now let's implement some basic security measures:

##### 7.1: Configure Firewall (UFW)

```bash
# Allow SSH (important - do this first!)
sudo ufw allow OpenSSH

# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable the firewall
sudo ufw enable

# Check firewall status
sudo ufw status
```

**Warning**: Make sure SSH is allowed before enabling the firewall, or you may lock yourself out!

##### 7.2: Secure SSH Configuration

**Critical Security Best Practice**: Disabling SSH access for the root user is one of the most important security measures you can take. This prevents attackers from directly targeting the root account, which has unlimited system access. Instead, users must log in with a regular account and use `sudo` for administrative tasks, which provides better audit trails and reduces the risk of complete system compromise.

Edit the SSH configuration to improve security:

```bash
# Backup the original SSH config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Edit SSH configuration
sudo nano /etc/ssh/sshd_config
```

Make the following changes (uncomment or add these lines):

```bash
# CRITICAL: Disable root login via SSH (security best practice)
# This prevents direct root access and forces use of sudo for admin tasks
PermitRootLogin no

# Disable password authentication (use keys only)
PasswordAuthentication no

# Change default SSH port (optional but recommended)
# Port 2222

# Limit login attempts
MaxAuthTries 3

# Disable empty passwords
PermitEmptyPasswords no
```

**⚠️ CRITICAL WARNING**: Before disabling root login, **ensure you can successfully SSH into the server using your new user account**. If you disable root login and your new user's SSH key isn't properly configured, you may lock yourself out of the server!

**Important**: If you change the SSH port, remember to:
1. Update your firewall: `sudo ufw allow 2222/tcp`
2. Update your SSH connection: `ssh -p 2222 devops@your-server-ip`

After making changes, restart the SSH service:

```bash
# Test the configuration first
sudo sshd -t

# If no errors, restart SSH
sudo systemctl restart sshd
```

**Before closing your current SSH session**, open a new terminal and test connecting with the new user to ensure everything works:

```bash
# From your local machine
ssh devops@your-server-ip
```

##### 7.3: Configure Fail2ban

Fail2ban helps protect against brute-force attacks:

```bash
# Fail2ban should already be installed from Step 2
# Start and enable fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check status
sudo systemctl status fail2ban
```

##### 7.4: Set Up Automatic Security Updates

Enable automatic security updates:

```bash
# Install unattended-upgrades
sudo apt install -y unattended-upgrades

# Enable automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades
```

Select "Yes" when prompted to automatically download and install security updates.

##### 7.5: Configure Timezone

Set your server's timezone:

```bash
# List available timezones
sudo timedatectl list-timezones

# Set timezone (replace with your timezone, e.g., Europe/Berlin)
sudo timedatectl set-timezone Europe/Berlin

# Verify
timedatectl
```

#### Step 8: Final Verification

Before finishing, verify everything is working correctly:

```bash
# Check system information
uname -a

# Check disk space
df -h

# Check memory
free -h

# Check firewall status
sudo ufw status verbose

# Check SSH service
sudo systemctl status sshd
```

#### Security Checklist

- ✅ System packages updated
- ✅ Non-root user created with sudo access
- ✅ SSH key authentication configured
- ✅ Firewall (UFW) configured and enabled
- ✅ **SSH root login disabled** (critical security best practice)
- ✅ Password authentication disabled (keys only)
- ✅ Fail2ban installed and running
- ✅ Automatic security updates enabled
- ✅ Timezone configured

#### Next Steps

Your VPS is now configured with basic security measures. You can proceed to:
- Install Dokploy (see [Install dokploy](#install-dokploy) section)
- Set up additional services
- Configure monitoring tools

**Important Notes**:
- Always keep your SSH private key secure and never share it
- Regularly update your system: `sudo apt update && sudo apt upgrade -y`
- Monitor your server logs: `sudo journalctl -xe` for system issues
- Keep backups of important configurations and data

## Install dokploy

This section provides a step-by-step guide to install Dokploy on your VPS. Dokploy is an open-source alternative to Heroku, Vercel, and Netlify, designed to simplify application deployment and management using Docker and Traefik.

For system requirements, please see the [VPS Considerations](#vps-considerations) section.

### Step 1: Verify Port Availability

Check that the required ports are not already in use:

```bash
# Check if ports 80, 443, and 3000 are available
sudo ss -tulnp | grep -E ':(80|443|3000) '

# If any ports are in use, you'll need to stop those services first
# If no output, the ports are free and ready to use
```

**Note**: If you have a web server (Apache, Nginx) or other services using these ports, you'll need to stop or reconfigure them before installing Dokploy.

### Step 2: Update System Packages

Ensure your system is up to date:

```bash
# Update package list
sudo apt update

# Upgrade all packages
sudo apt upgrade -y

# Install essential tools (if not already installed)
sudo apt install -y curl wget git
```

### Step 3: Install Dokploy

Dokploy provides an automated installation script that handles Docker installation, Docker Swarm setup, and all necessary components.

#### Option A: Automated Installation (Recommended)

Run the official Dokploy installation script:

```bash
# Download and run the installation script
curl -sSL https://dokploy.com/install.sh | sh
```

This script will:
- Install Docker and Docker Compose (if not already installed)
- Initialize Docker Swarm
- Create Docker overlay network
- Deploy Dokploy services (Dokploy UI, PostgreSQL, Redis, Traefik)
- Configure the reverse proxy

The installation process typically takes 5-10 minutes depending on your server's resources and internet connection.

**What to expect during installation**:
- Docker installation and configuration
- Docker Swarm initialization
- Downloading and starting Docker containers
- Setting up Traefik reverse proxy
- Configuring PostgreSQL and Redis databases

#### Option B: Manual Installation (Advanced)

If you need more control over the installation (custom ports, environment variables, or specific configurations), refer to the [Dokploy Manual Installation Guide](https://docs.dokploy.com/docs/core/manual-installation).

Manual installation allows you to:
- Customize ports (PORT, TRAEFIK_PORT, TRAEFIK_SSL_PORT)
- Configure custom database URLs (DATABASE_URL, REDIS_HOST)
- Set timezone and other environment variables
- Fine-tune Docker Swarm configuration

### Step 4: Configure Firewall

Ensure your firewall allows the required ports:

```bash
# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow Dokploy dashboard (port 3000)
sudo ufw allow 3000/tcp

# Verify firewall rules
sudo ufw status verbose
```

**Security Note**: After setting up your domain and HTTPS (Step 6), you can optionally restrict direct IP access to port 3000 and only allow access via your domain.

### Step 5: Access Dokploy Dashboard

Once installation is complete, access the Dokploy web interface:

1. **Open your web browser** and navigate to:

   ```text
   http://your-server-ip:3000
   ```
   Replace `your-server-ip` with your actual VPS IP address.

2. **Initial Setup**: You'll be presented with the Dokploy setup wizard where you'll:
   - Create your admin account (email and password)
   - Configure initial settings

3. **Login**: After creating your admin account, you can log in to the Dokploy dashboard.

### Step 6: Configure Domain and SSL/TLS (Recommended for Production)

For production use, it's highly recommended to set up a domain name and enable HTTPS:

#### 6.1: Point Your Domain to Your Server

1. **Get your server's IP address**:
   ```bash
   hostname -I
   # or
   curl ifconfig.me
   ```

2. **Configure DNS**: In your domain registrar's DNS settings, add an A record:
   - **Type**: A
   - **Name**: `dokploy` (or your preferred subdomain)
   - **Value**: Your server's IP address
   - **TTL**: 3600 (or default)

3. **Wait for DNS propagation** (usually 5-60 minutes). Verify with:
   ```bash
   dig dokploy.yourdomain.com
   # or
   nslookup dokploy.yourdomain.com
   ```

#### 6.2: Configure Domain in Dokploy

1. **Access Dokploy Settings**:
   - Log in to Dokploy dashboard
   - Navigate to **Settings → Domains**

2. **Add Your Domain**:
   - Enter your domain (e.g., `dokploy.yourdomain.com`)
   - Save the configuration

3. **Enable HTTPS**:
   - Dokploy uses Traefik with Let's Encrypt for automatic SSL certificates
   - Enable HTTPS/SSL in the domain settings
   - Let's Encrypt will automatically issue and renew certificates

4. **Test Access**: Visit `https://dokploy.yourdomain.com` to verify SSL is working.

#### 6.3: Secure Access (Optional but Recommended)

After your domain and HTTPS are working correctly:

1. **Disable direct IP access** to port 3000 in your firewall:
   ```bash
   # Remove the rule allowing port 3000
   sudo ufw delete allow 3000/tcp
   ```

2. **Access Dokploy only via your domain**: `https://dokploy.yourdomain.com`

This prevents exposing the dashboard via direct IP access and improves security.

### Step 7: Verify Installation

Check that all Dokploy services are running:

```bash
# Check Docker Swarm services
sudo docker service ls

# Check running containers
sudo docker ps

# Check Dokploy logs (if needed)
sudo docker service logs dokploy_dokploy
```

You should see services for:
- `dokploy_dokploy` (main application)
- `dokploy_postgres` (database)
- `dokploy_redis` (cache)
- `dokploy_traefik` (reverse proxy)

### Step 8: Post-Installation Configuration

#### 8.1: Configure SSH Keys (for Remote/Build Servers)

If you plan to use Dokploy's remote server or build server features:

1. **Generate SSH Key in Dokploy**:
   - Go to **Settings → SSH Keys**
   - Click "Add SSH Key"
   - Provide a name and paste your public SSH key
   - Save the key

2. **Add Remote/Build Servers** (if needed):
   - Go to **Settings → Remote Servers** or **Build Servers**
   - Add your server details
   - Ensure Docker is installed on remote servers
   - Run the setup script provided by Dokploy

#### 8.2: Configure Notifications (Optional)

Set up email or other notification methods:
- Navigate to **Settings → Notifications**
- Configure your preferred notification channels

#### 8.3: Set Up Backups (Recommended)

Configure automatic backups for your applications:
- Navigate to **Settings → Backups**
- Configure backup schedules and storage destinations

### Troubleshooting

#### Installation Issues

If you encounter issues during installation:

```bash
# Check Docker status
sudo systemctl status docker

# Check Docker Swarm status
sudo docker info | grep Swarm

# View installation logs
sudo journalctl -u docker -n 50
```

#### Port Conflicts

If ports 80, 443, or 3000 are already in use:

```bash
# Find what's using the port
sudo lsof -i :80
sudo lsof -i :443
sudo lsof -i :3000

# Stop conflicting services or reconfigure Dokploy manually
```

#### Cannot Access Dashboard

1. **Check firewall rules**: Ensure ports are open
2. **Verify services are running**: `sudo docker service ls`
3. **Check Traefik logs**: `sudo docker service logs dokploy_traefik`
4. **Verify IP address**: Ensure you're using the correct server IP

#### Reset Password or 2FA

If you need to reset your admin password or 2FA:
- Refer to the [Dokploy Reset Password & 2FA Guide](https://docs.dokploy.com/docs/core/reset-password-2fa)

### Next Steps

Now that Dokploy is installed and configured, you can:

1. **Deploy Applications**: Learn how to deploy your first application in the [Applications Guide](https://docs.dokploy.com/docs/core/applications)
2. **Set Up Databases**: Deploy databases like PostgreSQL, MySQL, MongoDB, etc. via the [Databases Guide](https://docs.dokploy.com/docs/core/databases)
3. **Use Docker Compose**: Deploy multi-container applications using [Docker Compose](https://docs.dokploy.com/docs/core/docker-compose)
4. **Configure Git Sources**: Connect your Git repositories for automatic deployments
5. **Set Up S3 Destinations**: Configure cloud storage for backups and media

### Additional Resources

- **Official Documentation**: [Dokploy Core Docs](https://docs.dokploy.com/docs/core)
- **Installation Guide**: [Dokploy Installation](https://docs.dokploy.com/docs/core/installation)
- **Manual Installation**: [Manual Installation Guide](https://docs.dokploy.com/docs/core/manual-installation)
- **Troubleshooting**: [Dokploy Troubleshooting](https://docs.dokploy.com/docs/core/troubleshooting)
- **Videos**: Check the [Videos section](https://docs.dokploy.com/docs/core/videos) for visual guides



## VPS Considerations

When planning your VPS setup, consider the services you'll be hosting. Below are recommendations for two common scenarios.

### Scenario 1: Dokploy + Supabase + n8n + 1-3 Next.js Apps with PayloadCMS

This is the full stack including a self-hosted Supabase instance for database, authentication, and storage.

#### Individual Component Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Dokploy** | 1 vCPU, 1-2 GB RAM | 2 vCPUs, 2-4 GB RAM |
| **Supabase (self-hosted)** | 2 vCPUs, 4 GB RAM, 50 GB SSD | 4+ vCPUs, 8-16 GB RAM, 100-200 GB SSD |
| **n8n** | 1 vCPU, 2 GB RAM, 20 GB SSD | 2-4 vCPUs, 4-8 GB RAM, 40-80 GB NVMe SSD |
| **Next.js + PayloadCMS** (per app) | 2 GB RAM, 20 GB disk | 4-6 GB RAM, 30-50 GB disk per app |

#### Combined VPS Recommendations

| Tier | CPU | RAM | Storage | Use Case |
|------|-----|-----|---------|----------|
| **Minimum Viable** | 4-6 vCPUs | 16 GB | 200-250 GB NVMe SSD | Development, low traffic, 1-2 Next.js apps |
| **Recommended Production** | 8 vCPUs | 32 GB | 500 GB NVMe SSD | Production, moderate traffic, 1-3 Next.js apps, active workflows |
| **High Traffic / Growth** | 12+ vCPUs | 64 GB | 1 TB NVMe SSD + object storage | High traffic, many concurrent users, heavy workflows, large media files |

#### Recommended Hetzner Server Types (Scenario 1)

- **Minimum**: CPX41 (8 vCPU, 16 GB RAM) - may be tight, consider upgrading
- **Recommended**: CCX23 (8 vCPU, 32 GB RAM) or CCX33 (12 vCPU, 48 GB RAM)
- **Production**: CCX33 (12 vCPU, 48 GB RAM) or higher

### Scenario 2: Dokploy + n8n + 1-3 Next.js Apps with PayloadCMS

This scenario excludes Supabase, assuming you'll use an external database or PayloadCMS's built-in database options.

#### Individual Component Requirements

| Component | Resource Needs |
|-----------|----------------|
| **Dokploy** | 1-2 vCPU, 2-4 GB RAM (orchestration overhead) |
| **n8n** | 2-4 vCPU, 4-8 GB RAM (spikes during workflow execution) |
| **Next.js + PayloadCMS** (per app) | 2-4 vCPU, 4-6 GB RAM, 30-50 GB disk per app |

#### Combined VPS Recommendations

| Tier | CPU | RAM | Storage | Use Case |
|------|-----|-----|---------|----------|
| **Minimum Viable** | 4 vCPUs | 12-16 GB | 150-200 GB NVMe SSD | Development, low traffic, 1 Next.js app |
| **Recommended Production** | 6-8 vCPUs | 24-32 GB | 300-500 GB NVMe SSD | Production, moderate traffic, 1-3 Next.js apps, active n8n workflows |
| **High Traffic / Growth** | 8-12 vCPUs | 48-64 GB | 500 GB+ NVMe SSD + object storage | High traffic, multiple concurrent users, complex workflows, large media files |

#### Recommended Hetzner Server Types (Scenario 2)

- **Cost-Effective**: CPX41 (8 vCPU, 16 GB RAM, 240 GB NVMe SSD)
  - Good for: 1-2 Next.js apps, moderate n8n usage
  - Note: May need to monitor RAM during builds

- **Recommended**: CCX23 (8 vCPU, 32 GB RAM, 200 GB NVMe SSD) ⭐
  - Good for: 2-3 Next.js apps, active n8n workflows, production use
  - Best balance of performance and cost

- **High Performance**: CCX33 (12 vCPU, 48 GB RAM, 400 GB NVMe SSD)
  - Good for: 3 Next.js apps, heavy n8n usage, high traffic, growth headroom

### Important Considerations for Both Scenarios

1. **Build Processes**: Next.js builds can spike RAM usage (8-12 GB per build). Ensure sufficient headroom so builds don't impact running services.

2. **Database**:
   - If using Supabase, PostgreSQL requires significant RAM for caching (4-8 GB minimum)
   - PayloadCMS can use PostgreSQL, MongoDB, or SQLite - allocate resources accordingly

3. **Media Storage**: If PayloadCMS serves many images/files, consider external object storage (S3-compatible) to avoid filling your VPS disk.

4. **n8n Workflows**: Complex or frequent workflows increase CPU and RAM usage. Monitor resource consumption during peak workflow execution.

5. **Swap Space**: Configure 4-8 GB swap space to handle memory spikes during builds and workflow execution.

6. **Reverse Proxy**: Use Nginx or Caddy for SSL certificates, routing, and load balancing across multiple apps.

7. **Storage Type**: Always use NVMe/SSD storage. Slow disks significantly impact database performance, build times, and media handling.

8. **Network Bandwidth**: Ensure good bandwidth for HTTP/HTTPS traffic and WebSockets (Supabase realtime, n8n webhooks).

9. **Monitoring**: Set up monitoring for CPU, RAM, and disk usage to identify bottlenecks early.

10. **Backups**: Plan for regular backups of databases and volumes, especially for production deployments.
