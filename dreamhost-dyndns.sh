#!/usr/bin/env bash

# Help function
show_help() {
    cat << EOF
DreamHost Dynamic DNS Updater
=============================

DESCRIPTION:
    Updates DNS A records for domains listed in domains.csv with your current external IP.
    Designed to minimize API calls due to DreamHost's hourly rate limits.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --help, -h      Show this help message
    --dry-run, -n   Show what changes would be made without executing them
    --quiet, -q     Run without prompts (suitable for cron jobs)

FILES:
    .env            Configuration file containing DREAMHOST_API_KEY
    domains.csv     Input file with format: TYPE,DOMAIN (e.g., A,example.com)
    dns.txt         Current DNS records from DreamHost API
    dns_final.txt   Final DNS records after changes (for verification)

IMPORTANT LIMITATIONS:
    • DreamHost API has hourly rate limits for DNS changes
    • Each DNS record creation/deletion counts toward your limit
    • This script minimizes API calls by:
      - Only making changes when IP actually differs
      - Only deleting records that need updating
      - Skipping domains already pointing to correct IP
      - Showing planned changes before execution

BEHAVIOR:
    CREATE  - Add new DNS record (no existing record found)
    UPDATE  - Replace old IP with new IP (delete old + create new)
    CLEANUP - Remove duplicate records with wrong IPs
    SKIP    - No changes needed (already correct)

EXAMPLES:
    $0                  # Update DNS records (interactive)
    $0 --dry-run        # Preview changes without making them
    $0 --quiet          # Update DNS records without prompts (for cron)
    $0 --help           # Show this help

PREREQUISITES:
    • Valid DreamHost API key in .env file (DREAMHOST_API_KEY=your_key)
    • domains.csv file with list of domains to update
    • curl command available

API KEY SETUP:
    1. Log into DreamHost panel
    2. Go to 'Advanced' -> 'API'
    3. Generate key with 'dns-*' permissions
    4. Create .env file: echo "DREAMHOST_API_KEY=your_key_here" > .env
    5. Secure the file: chmod 600 .env

SECURITY NOTE:
    • .env file contains sensitive API key - keep it secure
    • Add .env to .gitignore to prevent committing to repositories
    • Restrict API key permissions to only 'dns-*' operations
    • Set file permissions: chmod 600 .env

For more info: https://help.dreamhost.com/hc/en-us/articles/4407354972692
EOF
}

# Check for help flag
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Check for flags
DRY_RUN=false
QUIET_MODE=false

for arg in "$@"; do
    case $arg in
        --dry-run|-n)
            DRY_RUN=true
            echo "=== DRY RUN MODE - NO CHANGES WILL BE MADE ==="
            ;;
        --quiet|-q)
            QUIET_MODE=true
            ;;
        *)
            # Unknown argument
            if [[ $arg == --* ]]; then
                echo "Unknown option: $arg"
                echo "Use --help for usage information."
                exit 1
            fi
            ;;
    esac
done

SCRIPTLINK=$(readlink -f "$0")
SCRIPTDIR=$(dirname "${SCRIPTLINK}")

# Load API key from .env file
ENV_FILE="${SCRIPTDIR}/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env file not found at ${ENV_FILE}"
  echo "Create a .env file with:"
  echo "  DREAMHOST_API_KEY=your_api_key_here"
  echo "Use --help for more information."
  exit 1
fi

# Source the .env file
source "$ENV_FILE"

# Validate API key is set and not empty
if [ -z "$DREAMHOST_API_KEY" ]; then
  echo "ERROR: DREAMHOST_API_KEY not set or empty in .env file"
  echo "Add the following line to ${ENV_FILE}:"
  echo "  DREAMHOST_API_KEY=your_api_key_here"
  echo "Use --help for more information."
  exit 1
fi

API_KEY="$DREAMHOST_API_KEY"

# Check if domains.csv exists
if [ ! -f "${SCRIPTDIR}/domains.csv" ]; then
  echo "ERROR: domains.csv file not found in ${SCRIPTDIR}"
  echo "Create a domains.csv file with format: TYPE,DOMAIN"
  echo "Example: A,example.com"
  echo "Use --help for more information."
  exit 1
fi

# Get external IP with fallback options for reliability
get_external_ip() {
  local ip=""
  local services=(
    "https://checkip.amazonaws.com"
    "https://owljet.com/ip"
  )
  
  for service in "${services[@]}"; do
    echo "Trying $service..." >&2
    ip=$(curl -s --connect-timeout 5 --max-time 10 "$service" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | head -1)
    if [ -n "$ip" ]; then
      echo "✓ Got IP from $service: $ip" >&2
      echo "$ip"
      return 0
    fi
    echo "✗ Failed to get IP from $service" >&2
  done
  
  echo "ERROR: Failed to get external IP from all services" >&2
  return 1
}

ip=$(get_external_ip) || exit 1
if [ -z "$ip" ]; then
  echo "ERROR: External IP is empty"
  exit 1
else
  echo "Current External IP: $ip"
fi

# Read the array from domains.csv file
mapfile -t entries < ${SCRIPTDIR}/domains.csv

# Echo out the number of csv entries
echo "Number of CSV entries: ${#entries[@]}"

# Iterate through the DNS entries and ensure that they are only A, CNAME, NS, NAPTR, SRV, TXT, or AAAA
for entry in "${entries[@]}"
do
  IFS=',' read -r type dns_entry <<< "$entry"
  if [[ "$type" != "A" && "$type" != "CNAME" && "$type" != "NS" && "$type" != "NAPTR" && "$type" != "SRV" && "$type" != "TXT" && "$type" != "AAAA" ]]; then
    echo "Unsupported record type ${type} found in CSV file for entry : $dns_entry"
    exit 1
  fi
done

# If dns.txt exists, delete it
if [ -f "${SCRIPTDIR}/dns.txt" ]; then
  rm ${SCRIPTDIR}/dns.txt
fi

# Get list of all DNS records
curl -s "https://api.dreamhost.com/?key=$API_KEY&cmd=dns-list_records" > ${SCRIPTDIR}/dns.txt

# Check if the DNS query was successful by counting the number of lines in the file
if [ $(wc -l < ${SCRIPTDIR}/dns.txt) -lt 1 ]; then
  echo "DNS Query failed"
  exit 1
fi

# Read the DNS records from the file into an array called all_records
mapfile -t all_records < ${SCRIPTDIR}/dns.txt

# echo out the number of lines in the array
echo -e "Total Number of DNS records: ${#all_records[@]}\n"

# First pass: analyze what changes are needed
echo "=== ANALYZING CHANGES NEEDED ==="
total_changes=0
declare -a changes_needed

for entry in "${entries[@]}"
do
  IFS=',' read -r type dns_entry <<< "$entry"
  
  # Count existing records
  dupe_counter=0
  correct_dupe_counter=0
  old_ips=()

  for record in "${all_records[@]}"
  do
    record_type=$(echo ${record} | awk '{print $4}')
    record_value=$(echo ${record} | awk '{print $3}')
    record_ip=$(echo ${record} | awk '{print $5}')

    if [[ "$record_value" == "$dns_entry" && "$record_type" == "$type" ]]; then
      dupe_counter=$((dupe_counter+1))
      if [[ "$record_ip" == "$ip" ]]; then
        correct_dupe_counter=$((correct_dupe_counter+1))
      else
        old_ips+=("$record_ip")
      fi
    fi
  done

  # Determine what changes are needed
  if [ $correct_dupe_counter -eq 0 ]; then
    if [ $dupe_counter -eq 0 ]; then
      echo "CREATE: ${type} ${dns_entry} → ${ip} (new record)"
      changes_needed+=("CREATE ${type} ${dns_entry} ${ip}")
      total_changes=$((total_changes+1))
    else
      echo "UPDATE: ${type} ${dns_entry} → ${ip} (replace ${old_ips[*]})"
      changes_needed+=("UPDATE ${type} ${dns_entry} ${ip} ${old_ips[*]}")
      total_changes=$((total_changes+${#old_ips[@]}+1))  # deletions + creation
    fi
  elif [ $dupe_counter -gt $correct_dupe_counter ]; then
    echo "CLEANUP: ${type} ${dns_entry} → remove duplicates with IPs: ${old_ips[*]}"
    changes_needed+=("CLEANUP ${type} ${dns_entry} ${old_ips[*]}")
    total_changes=$((total_changes+${#old_ips[@]}))
  else
    echo "SKIP: ${type} ${dns_entry} → ${ip} (already correct)"
  fi
done

echo -e "\nSUMMARY: ${total_changes} API calls needed"
if [ $total_changes -eq 0 ]; then
  echo "No changes needed - all DNS records are already correct!"
  exit 0
fi

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: Would make ${total_changes} API calls. Run without --dry-run to execute."
  exit 0
fi

if [ "$QUIET_MODE" = true ]; then
  echo "QUIET MODE: Proceeding with ${total_changes} API calls without confirmation."
else
  read -p "Proceed with these changes? (y/N): " confirm
  if [[ $confirm != [yY] ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

echo -e "\n=== EXECUTING CHANGES ==="

for entry in "${entries[@]}"
do
  IFS=',' read -r type dns_entry <<< "$entry"
  echo "Processing ${type} record for: ${dns_entry}..."
  echo "Current IP to set: ${ip}"

  # First pass, count the number of matching records. We're looking for duplicates with old IP addresses.
  dupe_counter=0
  correct_dupe_counter=0

  for record in "${all_records[@]}"
  do
    # Parse the record. Column 3 is the record and column 4 is the type
    record_type=$(echo ${record} | awk '{print $4}')
    record_value=$(echo ${record} | awk '{print $3}')
    record_ip=$(echo ${record} | awk '{print $5}')

    # If the record type and value match the entry type and value, then increment the dupe_counter
    if [[ "$record_value" == "$dns_entry" && "$record_type" == "$type" ]]; then
      dupe_counter=$((dupe_counter+1))
    fi

    # If the value, type and ip match, then increment the correct dupe counter
    if [[ "$record_value" == "$dns_entry" && "$record_type" == "$type" && "$record_ip" == "$ip" ]]; then
      correct_dupe_counter=$((correct_dupe_counter+1))
    fi
  done

  echo "Found ${dupe_counter} existing records, ${correct_dupe_counter} with correct IP"

  # If there were zero matching records, then just create the new record and move on to the next entry
  if [ $dupe_counter -eq 0 ]; then
    echo -e "Creating new record for ${type} ${dns_entry}...\n"
    curl -s "https://api.dreamhost.com/?key=$API_KEY&cmd=dns-add_record&record=$dns_entry&type=$type&value=$ip" > /dev/null
    continue
  fi

  # Only delete records if we have wrong IPs AND we need to create a new one
  # This conserves API calls by avoiding unnecessary deletions
  needs_update=false
  old_ips=()
  
  if [ $dupe_counter -gt 0 ] && [ $correct_dupe_counter -eq 0 ]; then
    needs_update=true
    echo "IP change detected for ${type} ${dns_entry} - need to update records"
    
    # Collect old IPs first
    for record in "${all_records[@]}"
    do
      record_type=$(echo ${record} | awk '{print $4}')
      record_value=$(echo ${record} | awk '{print $3}')
      record_ip=$(echo ${record} | awk '{print $5}')

      if [[ "$record_value" == "$dns_entry" && "$record_type" == "$type" && "$record_ip" != "$ip" ]]; then
        old_ips+=("$record_ip")
      fi
    done
    
    echo "Will replace IP(s): ${old_ips[*]} with: ${ip}"
    
    # Now delete old records
    for record in "${all_records[@]}"
    do
      record_type=$(echo ${record} | awk '{print $4}')
      record_value=$(echo ${record} | awk '{print $3}')
      record_ip=$(echo ${record} | awk '{print $5}')

      if [[ "$record_value" == "$dns_entry" && "$record_type" == "$type" && "$record_ip" != "$ip" ]]; then
        echo "Deleting old record: ${record_type} ${record_value} ${record_ip}"
        curl -s "https://api.dreamhost.com/?key=$API_KEY&cmd=dns-remove_record&record=${record_value}&type=${record_type}&value=${record_ip}" > /dev/null
        sleep 1  # Reduced delay since we're being more careful about when to delete
      fi
    done
  elif [ $dupe_counter -gt 1 ] && [ $correct_dupe_counter -gt 0 ]; then
    # Handle case where we have the correct IP but also duplicates with wrong IPs
    echo "Found duplicates with wrong IPs for ${type} ${dns_entry} - cleaning up"
    for record in "${all_records[@]}"
    do
      record_type=$(echo ${record} | awk '{print $4}')
      record_value=$(echo ${record} | awk '{print $3}')
      record_ip=$(echo ${record} | awk '{print $5}')

      if [[ "$record_value" == "$dns_entry" && "$record_type" == "$type" && "$record_ip" != "$ip" ]]; then
        echo "Deleting duplicate record: ${record_type} ${record_value} ${record_ip}"
        curl -s "https://api.dreamhost.com/?key=$API_KEY&cmd=dns-remove_record&record=${record_value}&type=${record_type}&value=${record_ip}" > /dev/null
        sleep 1
      fi
    done
  fi

  # Only create new record if we don't have the correct one
  if [ $correct_dupe_counter -eq 0 ]; then
    if [ $needs_update = true ] || [ $dupe_counter -eq 0 ]; then
      echo "Creating new record for ${dns_entry} with IP ${ip}..."
      curl -s "https://api.dreamhost.com/?key=$API_KEY&cmd=dns-add_record&record=$dns_entry&type=$type&value=$ip" > /dev/null
      sleep 1
    fi
  fi

  # If we already have the correct record, don't do anything
  if [ $dupe_counter -eq 1 ] && [ $correct_dupe_counter -eq 1 ]; then
    echo -e "✓ Record for ${type} ${dns_entry} already correct (IP: ${ip}) - no changes needed\n"
  elif [ $correct_dupe_counter -gt 0 ]; then
    echo -e "✓ Record for ${type} ${dns_entry} updated successfully\n"
  fi
done

# Refresh DNS records after all changes for verification
echo "Refreshing DNS records for verification..."
curl -s "https://api.dreamhost.com/?key=$API_KEY&cmd=dns-list_records" > ${SCRIPTDIR}/dns_final.txt
echo "Updated DNS records saved to dns_final.txt"
