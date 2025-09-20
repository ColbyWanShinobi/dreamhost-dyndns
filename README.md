# DreamHost Dynamic DNS Updater

A smart, API-efficient script for updating DreamHost DNS A records with your current external IP address. Designed to minimize API calls and respect DreamHost's hourly rate limits.

## 🚀 Features

- **Smart Change Detection**: Only updates DNS when your IP actually changes
- **API Rate Limit Friendly**: Minimizes unnecessary API calls to stay within DreamHost limits
- **Multiple IP Services**: Uses fallback service for reliable external IP detection
- **Duplicate Cleanup**: Automatically removes duplicate DNS records
- **Dry Run Mode**: Preview changes before executing them
- **Comprehensive Logging**: Clear status messages and change summaries
- **Secure Configuration**: API key stored in protected `.env` file

## 📋 Prerequisites

- Linux/Unix system with bash
- `curl` command available
- DreamHost account with API access
- Domains hosted on DreamHost

## 🔧 Installation

### 1. Clone or Download

```bash
git clone https://github.com/ColbyWanShinobi/dreamhost-dyndns.git
cd dreamhost-dyndns
```

### 2. Get Your DreamHost API Key

1. Log into your [DreamHost Panel](https://panel.dreamhost.com)
2. Go to **Advanced** → **API**
3. Create a new API key with `dns-*` permissions
4. Copy the generated key

### 3. Configure the Script

```bash
# Copy the example configuration
cp .env.example .env

# Edit the configuration file
nano .env
```

Update `.env` with your API key:
```bash
DREAMHOST_API_KEY=your_actual_api_key_here
```

### 4. Secure the Configuration

```bash
# Set secure permissions (owner read/write only)
chmod 600 .env

# Verify permissions
ls -la .env
# Should show: -rw------- 1 user user
```

### 5. Create Domain List

Create `domains.csv` with the domains you want to update:

```bash
nano domains.csv
```

Format: `TYPE,DOMAIN` (one per line)
```csv
A,example.com
A,www.example.com
A,subdomain.example.com
A,blog.example.com
```

### 6. Make Script Executable

```bash
chmod +x dreamhost-dyndns.sh
```

## 🎯 Usage

### Basic Commands

```bash
# Show help and options
./dreamhost-dyndns.sh --help

# Preview changes without making them (recommended first run)
./dreamhost-dyndns.sh --dry-run

# Execute DNS updates (with confirmation prompt)
./dreamhost-dyndns.sh

# Execute DNS updates without prompts (for automation/cron)
./dreamhost-dyndns.sh --quiet

# Combine options: preview in quiet mode (useful for testing automation)
./dreamhost-dyndns.sh --quiet --dry-run
```

### Example Workflow

```bash
# 1. First, always do a dry run to see what will happen
./dreamhost-dyndns.sh --dry-run

# Sample output:
# Current External IP: 192.168.1.100
# === ANALYZING CHANGES NEEDED ===
# UPDATE: A example.com → 192.168.1.100 (replace 192.168.1.50)
# SKIP: A www.example.com → 192.168.1.100 (already correct)
# SUMMARY: 1 API calls needed

# 2. Interactive mode (prompts for confirmation)
./dreamhost-dyndns.sh
# Will prompt: "Proceed with these changes? (y/N):"

# 3. Automated mode (no prompts - for cron jobs)
./dreamhost-dyndns.sh --quiet
# Runs automatically without user interaction
```

### Automation vs Interactive Modes

- **Interactive Mode** (default): Prompts for confirmation before making changes
- **Quiet Mode** (`--quiet`): Runs without prompts, suitable for cron jobs and automation
- **Dry Run Mode** (`--dry-run`): Shows what would happen without making any changes

## 📖 Understanding the Output

The script shows different actions for each domain:

- **CREATE**: New DNS record (domain not found)
- **UPDATE**: Replace old IP with new IP
- **CLEANUP**: Remove duplicate records with wrong IPs
- **SKIP**: No changes needed (already correct)

## ⚙️ Configuration Files

### `.env` - API Configuration
```bash
# Required: Your DreamHost API key
DREAMHOST_API_KEY=your_key_here
```

### `domains.csv` - Domain List
```csv
A,example.com
A,www.example.com
A,blog.example.com
```

**Supported DNS Record Types:**
- `A` - IPv4 address (most common)
- `AAAA` - IPv6 address
- `CNAME` - Canonical name
- `TXT` - Text record
- `SRV` - Service record
- `NS` - Name server
- `NAPTR` - Naming authority pointer

## 🔒 Security Best Practices

### File Permissions
```bash
# Secure your configuration
chmod 600 .env
chmod 755 dreamhost-dyndns.sh
chmod 644 domains.csv
```

### Git Security
The `.env` file is automatically excluded from git via `.gitignore`. Never commit your API key!

### API Key Security
- Use minimum required permissions (`dns-*` only)
- Regenerate keys periodically
- Monitor API usage in DreamHost panel

## 🤖 Automation

### Cron Job Setup

For automatic updates, add to your crontab:

```bash
# Edit crontab
crontab -e

# Run every 30 minutes (quiet mode for automation)
*/30 * * * * /path/to/dreamhost-dyndns/dreamhost-dyndns.sh --quiet >/dev/null 2>&1

# Run every hour with logging (quiet mode)
0 * * * * /path/to/dreamhost-dyndns/dreamhost-dyndns.sh --quiet >> /var/log/dyndns.log 2>&1

# Run daily at 2 AM (quiet mode)
0 2 * * * /path/to/dreamhost-dyndns/dreamhost-dyndns.sh --quiet

# Run with dry-run first, then actual update (advanced setup)
*/30 * * * * /path/to/dreamhost-dyndns/dreamhost-dyndns.sh --dry-run && /path/to/dreamhost-dyndns/dreamhost-dyndns.sh --quiet
```

### Systemd Timer (Alternative)

Create a systemd service and timer for more robust automation:

```bash
# Create service file
sudo nano /etc/systemd/system/dreamhost-dyndns.service
```

```ini
[Unit]
Description=DreamHost Dynamic DNS Updater
After=network.target

[Service]
Type=oneshot
User=your_username
WorkingDirectory=/path/to/dreamhost-dyndns
ExecStart=/path/to/dreamhost-dyndns/dreamhost-dyndns.sh --quiet
```

```bash
# Create timer file
sudo nano /etc/systemd/system/dreamhost-dyndns.timer
```

```ini
[Unit]
Description=Run DreamHost Dynamic DNS Updater
Requires=dreamhost-dyndns.service

[Timer]
OnCalendar=*:0/30  # Every 30 minutes
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable dreamhost-dyndns.timer
sudo systemctl start dreamhost-dyndns.timer

# Check status
sudo systemctl status dreamhost-dyndns.timer
```

## ⚠️ Important Limitations

### DreamHost API Rate Limits
- DreamHost has **hourly limits** on DNS API calls
- Each DNS record creation/deletion counts toward your limit
- This script minimizes API usage by:
  - Only making changes when IP differs
  - Skipping domains already pointing to correct IP
  - Showing planned changes before execution
  - Batching operations efficiently

### IP Detection
The script uses multiple external services for IP detection:
1. `checkip.amazonaws.com`
2. `owljet.com/ip`

If all services fail, the script will exit with an error.

## 🔍 Troubleshooting

### Common Issues

**"ERROR: .env file not found"**
```bash
# Create the configuration file
cp .env.example .env
# Edit with your API key
nano .env
```

**"ERROR: DREAMHOST_API_KEY not set or empty"**
```bash
# Check your .env file has the key
cat .env
# Should contain: DREAMHOST_API_KEY=your_key_here
```

**"DNS Query failed"**
- Check your API key is valid
- Verify network connectivity
- Ensure API key has `dns-*` permissions

**"Failed to get external IP from all services"**
- Check internet connectivity
- Verify firewall allows outbound HTTPS
- Try manual IP detection: `curl https://api.ipify.org`

### Debug Mode

For debugging, you can run individual components:

```bash
# Test IP detection
curl -s https://api.ipify.org

# Test API connectivity
curl -s "https://api.dreamhost.com/?key=YOUR_KEY&cmd=dns-list_records" | head -5

# Validate domains.csv format
cat domains.csv
```

### Log Files

The script creates these files during operation:
- `dns.txt` - Current DNS records from API
- `dns_final.txt` - Final DNS records after changes (for verification)

## 📝 File Structure

```
dreamhost-dyndns/
├── .env                    # API configuration (create from .env.example)
├── .env.example           # Configuration template
├── .gitignore             # Git exclusions (includes .env)
├── README.md              # This documentation
├── dreamhost-dyndns.sh    # Main script
├── domains.csv            # List of domains to update
├── dns.txt                # Current DNS records (generated)
└── dns_final.txt          # Final DNS records (generated)
```

## 🔗 Links

- [DreamHost API Documentation](https://help.dreamhost.com/hc/en-us/articles/4407354972692)
- [DreamHost Panel](https://panel.dreamhost.com)
- [Script Repository](https://github.com/ColbyWanShinobi/dreamhost-dyndns)

## 📄 License

This project is open source. Feel free to modify and distribute.

## 🤝 Contributing

Issues and pull requests welcome! Please ensure you:
- Test changes thoroughly
- Update documentation as needed
- Follow existing code style
- Never commit API keys or sensitive data
