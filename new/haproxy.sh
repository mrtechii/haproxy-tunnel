#!/bin/bash

# ==========================================================
# === HAProxy Dynamic Port Forwarding Manager (Bash-Only) ===
# ==========================================================
# This script manages HAProxy configurations for dynamic port forwarding
# entirely within Bash, without any Python dependencies.
#
# UPDATES IN THIS VERSION:
# - Fixes Ctrl+C issue: Proper signal trapping for graceful exit on Ctrl+C.
# - Automatically configures systemd-journald to suppress "Broadcast message"
#   for HAProxy logs (e.g., "no server available!") from the terminal.
#   Logs are still fully recorded in systemd-journald.
# - Robust IPv6 validation and formatting are confirmed.
# - Auto-applies HAProxy config and shows status after Add/Edit/Delete.
# - Finalized color scheme and boldness based on user's specific requests.
# - FIX: Corrects HAProxy configuration validation error "No such file or directory"
#        by adding -V flag to haproxy -c command.

# --- Configuration & File Paths ---
HAPROXY_CONFIG_PATH="/etc/haproxy/haproxy.cfg"
HAPROXY_TEMP_CONFIG="/tmp/haproxy_generated.cfg" # Temporary file for validation before deployment
DATA_FILE="$HOME/.haproxy_tunnels_data" # Hidden file in home directory to store tunnels and health check port
JOURNALD_CONFIG_PATH="/etc/systemd/journald.conf" # Path to journald configuration file

# --- ANSI Color Codes ---
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m' # Dark Blue for List Tunnels and separators
MAGENTA='\033[0;35m' # Purple
CYAN='\033[0;36m'
WHITE='\033[0;37m'

BRIGHT_RED='\033[0;91m'
BRIGHT_GREEN='\033[0;92m'
BRIGHT_YELLOW='\033[0;93m'
BRIGHT_BLUE='\033[0;94m'
BRIGHT_MAGENTA='\033[0;95m' # Bright Purple for error messages
BRIGHT_CYAN='\033[0;96m'
BRIGHT_WHITE='\033[0;97m'

ORANGE='\033[38;5;208m' # Custom orange for consistency

NC='\033[0m' # No Color / Reset
BOLD=$(tput bold 2>/dev/null)
NORMAL=$(tput sgr0 2>/dev/null)
if [[ -z "$BOLD" ]]; then BOLD=""; fi # Fallback if tput is not available
if [[ -z "$NORMAL" ]]; then NORMAL=""; fi # Fallback if tput is not available


# --- Global Variables for Data Storage ---
# Stores tunnels as an array of strings, each string is a JSON-like object
# Format: {"backend_ip":"IP1,IP2","ports":"P1,P2","mode":"tcp/http"}
TUNNELS=()
HEALTH_CHECK_PORT=""

# --- Utility Functions for Colored Messages ---

error_msg() {
    echo -e "${BRIGHT_MAGENTA}${BOLD}Error:${NORMAL} $1${NC}" >&2
    return 1 # Indicate error
}

success_msg() {
    echo -e "${BRIGHT_GREEN}${BOLD}Success:${NORMAL} $1${NC}"
}

info_msg() {
    echo -e "${BRIGHT_BLUE}${BOLD}Info:${NORMAL} $1${NC}"
}

warn_msg() {
    echo -e "${BRIGHT_YELLOW}${BOLD}Warning:${NORMAL} $1${NC}"
}

# --- Data Persistence Functions ---

load_data() {
    TUNNELS=() # Clear existing tunnels
    HEALTH_CHECK_PORT="" # Clear existing port

    if [[ -f "$DATA_FILE" ]]; then
        info_msg "Loading configuration from ${CYAN}${DATA_FILE}${NC}..."
        # Read HEALTH_CHECK_PORT first
        HEALTH_CHECK_PORT=$(grep '^HEALTH_CHECK_PORT=' "$DATA_FILE" | cut -d= -f2- | head -n 1)
        if [[ -z "$HEALTH_CHECK_PORT" ]]; then
            HEALTH_CHECK_PORT="" # Ensure it's empty if not found
        fi

        # Read TUNNELS
        local in_tunnel_block=0
        local current_tunnel_data=""
        while IFS= read -r line; do
            if [[ "$line" == "TUNNEL_START" ]]; then
                in_tunnel_block=1
                current_tunnel_data=""
                continue
            elif [[ "$line" == "TUNNEL_END" ]]; then
                in_tunnel_block=0
                TUNNELS+=("$current_tunnel_data")
                continue
            fi

            if [[ "$in_tunnel_block" -eq 1 ]]; then
                current_tunnel_data+="$line"
            fi
        done < "$DATA_FILE"
        success_msg "Configuration loaded."
    else
        warn_msg "Data file '${CYAN}${DATA_FILE}${NC}' not found. Starting with empty configuration."
    fi
}

save_data() {
    info_msg "Saving configuration to ${CYAN}${DATA_FILE}${NC}..."
    # Clear existing file
    > "$DATA_FILE"

    echo "HEALTH_CHECK_PORT=$HEALTH_CHECK_PORT" >> "$DATA_FILE"

    for tunnel_str in "${TUNNELS[@]}"; do
        echo "TUNNEL_START" >> "$DATA_FILE"
        echo "$tunnel_str" >> "$DATA_FILE"
        echo "TUNNEL_END" >> "$DATA_FILE"
    done
    success_msg "Configuration saved."
}

# --- Validation Functions ---

is_valid_single_ip() {
    local ip="$1"
    # IPv4 regex
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet < 0 || octet > 255 )); then return 1; fi
        done
        return 0
    fi

    # IPv6 regex (more robust, covers various forms)
    if [[ "$ip" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]]; then return 0; fi # Full IPv6
    if [[ "$ip" =~ ^([0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){0,6})?::([0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){0,6})?$ ]]; then # Compressed IPv6
        if [[ "$(echo "$ip" | grep -o '::' | wc -l)" -le 1 ]]; then return 0; fi
    fi
    if [[ "$ip" =~ ^([0-9a-fA-F]{1,4}:){6}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; then return 0; fi # IPv6 with embedded IPv4

    return 1 # Not a valid IPv4 or IPv6
}

validate_ip() {
    local ips_str="$1"
    # Split by comma and check each IP
    IFS=',' read -r -a ADDR <<< "$ips_str"
    for i in "${ADDR[@]}"; do
        if ! is_valid_single_ip "$i"; then
            return 1 # Invalid IP format
        fi
    done
    return 0 # All IPs are valid
}

validate_ports() {
    local ports_str="$1"
    # Split by comma and check each port
    IFS=',' read -r -a PORTS <<< "$ports_str"
    for p in "${PORTS[@]}"; do
        # Check if it's a number and within valid port range
        if ! [[ "$p" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then
            return 1 # Invalid port
        fi
    done
    return 0 # All ports are valid
}

# --- User Input Functions ---

get_user_input() {
    local prompt_text="$1"
    local current_value="$2"
    local validation_func="$3"
    local error_message="$4"
    local result=""

    while true; do
        local display_prompt="${prompt_text}"; if [[ -n "$current_value" ]]; then display_prompt+=" (Current: ${current_value})"; fi
        read -rp "${display_prompt}: " user_input_val
        user_input_val="${user_input_val// /}" # Remove spaces for IP/port lists

        if [[ -z "$user_input_val" ]]; then # If user presses enter, keep current value
            result="$current_value"
            break
        fi

        if [[ -z "$validation_func" ]]; then # No validation needed
            result="$user_input_val"
            break
        elif "$validation_func" "$user_input_val"; then # Call validation function
            result="$user_input_val"
            break
        else
            error_msg "${error_message:-Invalid input. Please try again.}"
        fi
    done
    echo "$result" # Return the result
}

format_ip_for_haproxy() {
    local ip="$1"
    if [[ "$ip" =~ ":" ]] && [[ ! "$ip" =~ ^\[.*\]$ ]]; then echo "[$ip]"; else echo "$ip"; fi
}

# --- HAProxy Configuration Generation ---

generate_haproxy_config() {
    info_msg "Generating HAProxy configuration..."
    local config_content=""
    
    # Global settings
    config_content+="global\n"
    config_content+="    log /dev/log    local0\n" # This ensures logs go to syslog/journald
    config_content+="    chroot /var/lib/haproxy\n"
    config_content+="    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners\n"
    config_content+="    stats timeout 30s\n"
    config_content+="    user haproxy\n"
    config_content+="    group haproxy\n"
    config_content+="    daemon\n"
    config_content+="    maxconn 20000\n"
    config_content+="\n"

    # Default settings for listen sections
    config_content+="defaults\n"
    config_content+="    log             global\n"
    config_content+="    option          dontlog-normal\n" # Suppresses normal connection logs
    config_content+="    timeout connect 5s\n"
    config_content+="    timeout client  50s\n"
    config_content+="    timeout server  50s\n"
    config_content+="\n"

    # Separate listen sections for each tunnel to avoid "too many words" and allow individual modes
    local listen_sections_config="" tunnel_counter=0
    for tunnel_str in "${TUNNELS[@]}"; do
        local backend_ip_list_raw=$(echo "$tunnel_str" | sed -n 's/.*"backend_ip":"\([^"]*\)".*/\1/p')
        local ports_raw=$(echo "$tunnel_str" | sed -n 's/.*"ports":"\([^"]*\)".*/\1/p')
        local mode=$(echo "$tunnel_str" | sed -n 's/.*"mode":"\([^"]*\)".*/\1/p')
        
        if [[ -z "$backend_ip_list_raw" || -z "$ports_raw" ]]; then continue; fi

        IFS=',' read -r -a current_ports_array <<< "$ports_raw"
        IFS=',' read -r -a backend_ips_array <<< "$backend_ip_list_raw"

        for p in "${current_ports_array[@]}"; do
            local listen_name="listen_tunnel_${tunnel_counter}_port_${p}"
            listen_sections_config+="\nlisten ${listen_name}\n"
            listen_sections_config+="    bind *:${p}\n"
            listen_sections_config+="    mode ${mode}\n"
            
            # Specific log option based on mode
            if [[ "$mode" == "http" ]]; then
                listen_sections_config+="    option          httplog\n"
            else # tcp
                listen_sections_config+="    option          tcplog\n"
            fi
            # Add dontlognull to specific listen section for good measure
            listen_sections_config+="    option          dontlognull\n"

            local health_check_options=""
            local target_backend_port_for_service="${p}" # Assume backend listens on same port as frontend

            if [[ -n "$HEALTH_CHECK_PORT" ]]; then
                if [[ "$mode" == "http" ]]; then
                    health_check_options+="    option httpchk GET / HTTP/1.1\n"
                    health_check_options+="    http-check expect status 200\n"
                else # tcp
                    health_check_options+="    option tcp-check\n"
                    health_check_options+="    tcp-check connect port ${HEALTH_CHECK_PORT}\n"
                fi
            fi
            listen_sections_config+="$health_check_options"

            if [[ ${#backend_ips_array[@]} -gt 1 ]]; then
                listen_sections_config+="    balance roundrobin # Load balancing for multiple servers\n"
            fi
            
            for i in "${!backend_ips_array[@]}"; do
                local ip_to_format="${backend_ips_array[$i]}"; local formatted_ip=$(format_ip_for_haproxy "$ip_to_format")
                listen_sections_config+="    server srv${i} ${formatted_ip}:${target_backend_port_for_service} check\n"
            done
        done
        ((tunnel_counter++))
    done

    config_content+="$listen_sections_config"

    # Default backend for unmatched traffic (optional, but good practice)
    config_content+="\nbackend default_drop_backend\n"
    config_content+="    mode tcp\n"
    config_content+="    # This backend simply drops unmatched traffic if no other rules apply.\n"
    config_content+="\n"

    echo -e "$config_content" > "$HAPROXY_TEMP_CONFIG"

    info_msg "Validating generated HAProxy configuration..."
    # FIX: Add -V flag to haproxy -c to bypass chroot issue during validation
    sudo haproxy -c -V -f "$HAPROXY_TEMP_CONFIG"
    if [[ $? -ne 0 ]]; then
        error_msg "HAProxy configuration validation failed! Check the output above."
        return 1
    fi
    success_msg "HAProxy configuration validated successfully."
    return 0
}

apply_haproxy_config() {
    info_msg "Applying HAProxy configuration and restarting service..."

    # Generate config first
    generate_haproxy_config || return 1 # Exit function if config generation fails

    sudo cp "$HAPROXY_TEMP_CONFIG" "$HAPROXY_CONFIG_PATH" || \
        { error_msg "Failed to copy HAProxy configuration to ${CYAN}${HAPROXY_CONFIG_PATH}${NC}. Do you have root permissions?"; return 1; }

    sudo systemctl restart haproxy || \
        { error_msg "Failed to restart HAProxy service. Check 'sudo journalctl -u haproxy -f' for details."; return 1; }

    success_msg "HAProxy configuration applied and service restarted successfully."
    return 0 # Indicate success
}

show_haproxy_status() {
    echo -e "\n${BLUE}${BOLD}--- HAProxy Service Status ---${NORMAL}${NC}"
    sudo systemctl status haproxy --no-pager
    echo -e "${BLUE}------------------------------${NC}"
}

# --- Journald Configuration Function ---
configure_journald_for_logs() {
    info_msg "Configuring systemd-journald to reduce terminal log spam..."

    if [[ ! -f "$JOURNALD_CONFIG_PATH" ]]; then
        error_msg "Journald config file not found at ${CYAN}${JOURNALD_CONFIG_PATH}${NC}. Cannot configure log levels."
        return 1
    fi

    # Backup the original file
    sudo cp "$JOURNALD_CONFIG_PATH" "${JOURNALD_CONFIG_PATH}.bak"
    info_msg "Backed up ${CYAN}${JOURNALD_CONFIG_PATH}${NC} to ${CYAN}${JOURNALD_CONFIG_PATH}.bak${NC}."

    # Use sed to set/update ForwardToWall and MaxLevelWall
    # If the line exists and is commented, uncomment and set. If exists and not commented, just set. If not exists, append.

    # 1. Set ForwardToWall=no
    # Check if 'ForwardToWall' exists, if so, update it. Else, append it.
    if grep -qE '^\s*#?\s*ForwardToWall=' "$JOURNALD_CONFIG_PATH"; then
        sudo sed -i -E 's/^\s*#?\s*ForwardToWall=.*/ForwardToWall=no/' "$JOURNALD_CONFIG_PATH"
        info_msg "Updated 'ForwardToWall=no' in journald.conf."
    else
        echo "ForwardToWall=no" | sudo tee -a "$JOURNALD_CONFIG_PATH" > /dev/null
        info_msg "Added 'ForwardToWall=no' to journald.conf."
    fi

    # 2. Set MaxLevelWall=emerg
    if grep -qE '^\s*#?\s*MaxLevelWall=' "$JOURNALD_CONFIG_PATH"; then
        sudo sed -i -E 's/^\s*#?\s*MaxLevelWall=.*/MaxLevelWall=emerg/' "$JOURNALD_CONFIG_PATH"
        info_msg "Updated 'MaxLevelWall=emerg' in journald.conf."
    else
        echo "MaxLevelWall=emerg" | sudo tee -a "$JOURNALD_CONFIG_PATH" > /dev/null
        info_msg "Added 'MaxLevelWall=emerg' to journald.conf."
    fi

    # Restart journald service to apply changes
    info_msg "Restarting systemd-journald service..."
    sudo systemctl restart systemd-journald
    if [[ $? -eq 0 ]]; then
        success_msg "systemd-journald configured and restarted successfully. Broadcast messages should now be suppressed."
        return 0
    else
        error_msg "Failed to restart systemd-journald. You might need to restart it manually: 'sudo systemctl restart systemd-journald'."
        return 1
    fi
}


# --- Main CLI Menu Functions ---

list_tunnels() {
    echo -e "\n${BLUE}${BOLD}--- Current Tunnels ---${NORMAL}${NC}" # Dark Blue, Bold
    if [[ ${#TUNNELS[@]} -eq 0 ]]; then
        info_msg "No tunnels configured yet."
        echo -e "${BLUE}-----------------------${NC}"
        return
    fi
    for i in "${!TUNNELS[@]}"; do
        local tunnel_str="${TUNNELS[$i]}"
        # Extract values safely using string manipulation with sed
        local backend_ip=$(echo "$tunnel_str" | sed -n 's/.*"backend_ip":"\([^"]*\)".*/\1/p')
        local ports=$(echo "$tunnel_str" | sed -n 's/.*"ports":"\([^"]*\)".*/\1/p')
        local mode=$(echo "$tunnel_str" | sed -n 's/.*"mode":"\([^"]*\)".*/\1/p')

        echo -e "${MAGENTA}${BOLD}ID: $i${NORMAL}"
        echo -e "  ${YELLOW}Backend IP(s):${NORMAL} ${BRIGHT_GREEN}$backend_ip${NC}"
        echo -e "  ${YELLOW}Ports: ${NORMAL}${BRIGHT_GREEN}$ports${NC}"
        echo -e "  ${YELLOW}Mode: ${NORMAL}${BRIGHT_GREEN}$mode${NC}"
        echo -e "${BLUE}--------------------${NC}"
    done
    echo -e "${BRIGHT_BLUE}Default Health Check Port: ${BRIGHT_GREEN}${HEALTH_CHECK_PORT:-None}${NC}"
    echo -e "${BLUE}-----------------------${NC}"
}

add_tunnel() {
    echo -e "\n${BRIGHT_GREEN}${BOLD}--- Add New Tunnel ---${NORMAL}${NC}" # Brighter Green, Bold
    local backend_ip_val=$(get_user_input "Enter Backend IP(s) (comma-separated, e.g., 192.168.1.10,2001:db8::1)" "" "validate_ip" "Invalid IP format. Use comma-separated IPs like 192.168.1.1,2001:db8::1.")
    if [[ -z "$backend_ip_val" ]]; then warn_msg "Operation cancelled."; return; fi
    local ports_val=$(get_user_input "Enter Ports (comma-separated, e.g., 80,443,2222)" "" "validate_ports" "Invalid port format. Use comma-separated numbers like 80,443. Ports must be between 1 and 65535.")
    if [[ -z "$ports_val" ]]; then warn_msg "Operation cancelled."; return; fi
    local mode_val=""
    while true; do
        read -rp "Enter Mode (tcp/http, default: tcp): " mode_input
        mode_input="${mode_input,,}" # Convert to lowercase
        if [[ -z "$mode_input" ]]; then mode_val="tcp"; break;
        elif [[ "$mode_input" == "tcp" || "$mode_input" == "http" ]]; then mode_val="$mode_input"; break;
        else error_msg "Invalid mode. Enter 'tcp' or 'http'."; fi
    done
    local new_tunnel_json="{\"backend_ip\":\"$backend_ip_val\",\"ports\":\"$ports_val\",\"mode\":\"$mode_val\"}"
    TUNNELS+=("$new_tunnel_json")
    save_data
    success_msg "Tunnel added successfully."
    if apply_haproxy_config; then show_haproxy_status; fi
}

edit_tunnel() {
    echo -e "\n${ORANGE}${BOLD}--- Edit Tunnel ---${NORMAL}${NC}" # Orange, Bold
    list_tunnels
    if [[ ${#TUNNELS[@]} -eq 0 ]]; then return; fi
    local tunnel_id=""
    while true; do
        read -rp "Enter ID of tunnel to edit (or leave empty to cancel): " tunnel_id
        if [[ -z "$tunnel_id" ]]; then warn_msg "Operation cancelled."; return; fi
        if ! [[ "$tunnel_id" =~ ^[0-9]+$ ]] || (( tunnel_id < 0 || tunnel_id >= ${#TUNNELS[@]} )); then error_msg "Invalid tunnel ID."; else break; fi
    done
    local tunnel_str="${TUNNELS[$tunnel_id]}"
    local current_backend_ip=$(echo "$tunnel_str" | sed -n 's/.*"backend_ip":"\([^"]*\)".*/\1/p')
    local current_ports=$(echo "$tunnel_str" | sed -n 's/.*"ports":"\([^"]*\)".*/\1/p')
    local current_mode=$(echo "$tunnel_str" | sed -n 's/.*"mode":"\([^"]*\)".*/\1/p')
    
    echo -e "\n${YELLOW}Editing Tunnel ID: ${MAGENTA}${BOLD}${tunnel_id}${NORMAL}${NC} (Current Mode: ${CYAN}${current_mode}${NC})" # Bold ID
    local new_backend_ip=$(get_user_input "Enter new Backend IP(s)" "$current_backend_ip" "validate_ip" "Invalid IP format.")
    if [[ -z "$new_backend_ip" ]]; then warn_msg "Operation cancelled."; return; fi
    local new_ports=$(get_user_input "Enter new Ports" "$current_ports" "validate_ports" "Invalid port format.")
    if [[ -z "$new_ports" ]]; then warn_msg "Operation cancelled."; fi
    
    local new_mode_val=""
    while true; do
        read -rp "Enter new Mode (tcp/http, current: ${current_mode}): " new_mode_input
        new_mode_input="${new_mode_input,,}"
        if [[ -z "$new_mode_input" ]]; then new_mode_val="$current_mode"; break;
        elif [[ "$new_mode_input" == "tcp" || "$new_mode_input" == "http" ]]; then new_mode_val="$new_mode_input"; break;
        else error_msg "Invalid mode. Enter 'tcp' or 'http'."; fi
    done
    local updated_tunnel_json="{\"backend_ip\":\"$new_backend_ip\",\"ports\":\"$new_ports\",\"mode\":\"$new_mode_val\"}"
    TUNNELS[$tunnel_id]="$updated_tunnel_json"
    save_data
    success_msg "Tunnel updated successfully."
    if apply_haproxy_config; then show_haproxy_status; fi
}

delete_tunnel() {
    echo -e "\n${RED}${BOLD}--- Delete Tunnel ---${NORMAL}${NC}" # Red, Bold
    list_tunnels
    if [[ ${#TUNNELS[@]} -eq 0 ]]; then return; fi
    local tunnel_id=""
    while true; do
        read -rp "Enter ID of tunnel to delete (or leave empty to cancel): " tunnel_id
        if [[ -z "$tunnel_id" ]]; then warn_msg "Operation cancelled."; return; fi
        if ! [[ "$tunnel_id" =~ ^[0-9]+$ ]] || (( tunnel_id < 0 || tunnel_id >= ${#TUNNELS[@]} )); then error_msg "Invalid tunnel ID."; else break; fi
    done
    printf "${BRIGHT_RED}Are you sure you want to delete tunnel ID ${BOLD}${tunnel_id}${NORMAL}${BRIGHT_RED}? (y/n): ${NC}" # Bold tunnel ID in prompt
    read -r confirm
    confirm="${confirm,,}"
    if [[ "$confirm" == "y" ]]; then
        local temp_tunnels=(); for i in "${!TUNNELS[@]}"; do if [[ "$i" -ne "$tunnel_id" ]]; then temp_tunnels+=("${TUNNELS[$i]}"); fi; done; TUNNELS=("${temp_tunnels[@]}")
        save_data
        success_msg "Tunnel deleted successfully."
        if apply_haproxy_config; then show_haproxy_status; fi
    else info_msg "Deletion cancelled."; fi
}

manage_health_check_port() {
    echo -e "\n${CYAN}${BOLD}--- Manage Default Health Check Port ---${NORMAL}${NC}" # Cyan, Bold
    local new_port_val=$(get_user_input "Enter fixed default port for TCP health checks (e.g., 80, 22). Leave empty to disable." "$HEALTH_CHECK_PORT" "validate_ports" "Invalid port. Must be a number between 1 and 65535 or empty.")
    HEALTH_CHECK_PORT="$new_port_val"
    save_data
    success_msg "Default health check port updated."
    if apply_haproxy_config; then show_haproxy_status; fi
}

# --- Ctrl+C (SIGINT) handler ---
cleanup() {
    echo -e "\n${BRIGHT_RED}${BOLD}Ctrl+C detected. Exiting gracefully.${NORMAL}${NC}"
    exit 0
}

# Trap Ctrl+C (SIGINT)
trap cleanup SIGINT

# --- Main Menu ---

main_menu() {
    # Check for HAProxy installation at start
    if ! command -v haproxy &> /dev/null; then
        info_msg "HAProxy is not installed. Attempting to install..."
        sudo apt update && sudo apt install -y haproxy
        if [[ $? -ne 0 ]]; then
            error_msg "Failed to install HAProxy. Please install it manually or check your internet connection."
            return 1 # Exit main menu if HAProxy cannot be installed
        fi
        success_msg "HAProxy installed successfully."
    fi

    # Configure systemd-journald to suppress broadcast messages
    configure_journald_for_logs

    load_data # Load data when script starts

    while true; do
        echo -e "\n${BOLD}${MAGENTA}========== HAProxy Tunnel Manager (Bash CLI) ==========${NORMAL}${NC}" # Bold Purple
        echo -e "${BLUE}${BOLD}-------------------------------------------------------${NORMAL}${NC}" # Bold Dark Blue for separators
        echo -e "${BLUE}${BOLD}1. List Tunnels${NORMAL}${NC}" # Bold Dark Blue
        echo -e "${BRIGHT_GREEN}${BOLD}2. Add New Tunnel${NORMAL}${NC}" # Bold Brighter Green
        echo -e "${ORANGE}${BOLD}3. Edit Tunnel${NORMAL}${NC}" # Bold Orange
        echo -e "${RED}${BOLD}4. Delete Tunnel${NORMAL}${NC}" # Bold Red
        echo -e "${BLUE}${BOLD}-------------------------------------------------------${NORMAL}${NC}"
        echo -e "${CYAN}${BOLD}5. Manage Default Health Check Port${NORMAL}${NC}" # Bold Cyan
        echo -e "${CYAN}${BOLD}6. Apply HAProxy Configuration & Restart Service (Manual Trigger)${NORMAL}${NC}" # Bold Cyan
        echo -e "${YELLOW}${BOLD}7. Show HAProxy Service Status${NORMAL}${NC}" # Bold Yellow
        echo -e "${BLUE}${BOLD}-------------------------------------------------------${NORMAL}${NC}"
        echo -e "${BRIGHT_RED}${BOLD}8. Exit${NORMAL}${NC}" # Bold Bright Red
        echo -e "${BOLD}${MAGENTA}=======================================================${NORMAL}${NC}"
        
        # PROMPT IS UNCOLORED FOR STABILITY
        read -rp "Enter your choice (1-8): " choice

        case "$choice" in
            1) list_tunnels ;;
            2) add_tunnel ;;
            3) edit_tunnel ;;
            4) delete_tunnel ;;
            5) manage_health_check_port ;;
            6) apply_haproxy_config && show_haproxy_status ;;
            7) show_haproxy_status ;;
            8)
                info_msg "Exiting. Goodbye!"
                break
                ;;
            *)
                error_msg "Invalid choice. Please enter a number between 1 and 8."
                ;;
        esac
    done
}

# --- Script Entry Point ---
main_menu
