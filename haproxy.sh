#!/bin/bash

# ==========================================================
# === HAProxy Dynamic Port Forwarding Manager (Bash-Only) ===
# ==========================================================
# This script manages HAProxy configurations for dynamic port forwarding
# entirely within Bash, without any Python dependencies.
# This version aims to finally resolve all "too many words" and parsing errors,
# AND fixes the Bash syntax error.
# It includes automatic config application and status checks.

# --- Configuration & File Paths ---
HAPROXY_CONFIG_PATH="/etc/haproxy/haproxy.cfg"
HAPROXY_TEMP_CONFIG="/tmp/haproxy_generated.cfg" # Temporary file for validation before deployment
DATA_FILE="$HOME/.haproxy_tunnels_data" # Hidden file in home directory to store tunnels and health check port

# --- ANSI Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# --- Global Variables for Data Storage ---
# Stores tunnels as an array of strings, each string is a JSON-like object
# Format: {"backend_ip":"IP1,IP2","ports":"P1,P2","mode":"tcp/http"}
TUNNELS=()
HEALTH_CHECK_PORT=""

# --- Utility Functions ---

error_exit() {
    echo -e "${RED}${BOLD}Error:${NORMAL} $1${NC}" >&2
    # In interactive menu, we don't exit the script, just the function
    return 1
}

success_msg() {
    echo -e "${GREEN}${BOLD}Success:${NORMAL} $1${NC}"
}

info_msg() {
    echo -e "${BLUE}${BOLD}Info:${NORMAL} $1${NC}"
}

warn_msg() {
    echo -e "${YELLOW}Warning:${NORMAL} $1${NC}"
}

# --- Data Persistence Functions ---

load_data() {
    TUNNELS=() # Clear existing tunnels
    HEALTH_CHECK_PORT="" # Clear existing port

    if [[ -f "$DATA_FILE" ]]; then
        info_msg "Loading configuration from $DATA_FILE..."
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
        warn_msg "Data file '$DATA_FILE' not found. Starting with empty configuration."
    fi
}

save_data() {
    info_msg "Saving configuration to $DATA_FILE..."
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

validate_ip() {
    local ips_str="$1"
    # Split by comma and check each IP
    IFS=',' read -ra ADDR <<< "$ips_str"
    for i in "${ADDR[@]}"; do
        # Basic pattern match for IPv4
        if ! [[ "$i" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            return 1 # Invalid IP format
        fi
        # Check if each octet is within 0-255
        IFS='.' read -ra OCTETS <<< "$i"
        for octet in "${OCTETS[@]}"; do
            if (( octet < 0 || octet > 255 )); then
                return 1 # Octet out of range
            fi
        done
    done
    return 0 # All IPs are valid
}

validate_ports() {
    local ports_str="$1"
    # Split by comma and check each port
    IFS=',' read -ra PORTS <<< "$ports_str"
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
    local prompt="$1"
    local current_value="$2"
    local validation_func="$3"
    local error_message="$4"
    local result=""

    while true; do
        read -rp "${prompt} (Current: '$current_value'): " user_input_val
        user_input_val="${user_input_val// /}" # Remove spaces for IP/port lists

        if [[ -z "$user_input_val" ]]; then # If user presses enter, keep current value
            result="$current_value"
            break
        fi

        if [[ -z "$validation_func" ]]; then # No validation needed
            result="$user_input_val"
            break
        elif $validation_func "$user_input_val"; then # Call validation function
            result="$user_input_val"
            break
        else
            echo -e "${RED}Error: ${error_message} Please try again.${NC}"
        fi
    done
    echo "$result" # Return the result
}

# --- HAProxy Configuration Generation ---

generate_haproxy_config() {
    local config_content=""
    local frontend_mode_override="tcp" # Default to TCP
    declare -A unique_frontend_ports_mode # Associative array: port -> mode (tcp/http)

    # Determine frontend mode and gather all ports
    for tunnel_str in "${TUNNELS[@]}"; do
        local mode=$(echo "$tunnel_str" | grep -o '"mode":"[^"]*"' | cut -d: -f2 | tr -d '"')
        local ports=$(echo "$tunnel_str" | grep -o '"ports":"[^"]*"' | cut -d: -f2 | tr -d '"')
        
        IFS=',' read -ra current_ports_array <<< "$ports"
        for p in "${current_ports_array[@]}"; do
            # If a port is used by an HTTP backend, it forces the frontend to HTTP mode for that port.
            # Otherwise, it defaults to TCP.
            if [[ "$mode" == "http" ]]; then
                unique_frontend_ports_mode[$p]="http"
                frontend_mode_override="http" # If any tunnel is HTTP, frontend must be HTTP
            elif [[ -z "${unique_frontend_ports_mode[$p]}" ]]; then # Only set to TCP if not already HTTP
                unique_frontend_ports_mode[$p]="tcp"
            fi
        done
    done

    # Start building config_content with proper newlines
    config_content+="global\n"
    config_content+="    log /dev/log    local0\n"
    config_content+="    chroot /var/lib/haproxy\n"
    config_content+="    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners\n"
    config_content+="    stats timeout 30s\n"
    config_content+="    user haproxy\n"
    config_content+="    group haproxy\n"
    config_content+="    daemon\n"
    config_content+="    maxconn 20000\n"
    config_content+="\n"

    config_content+="defaults\n"
    config_content+="    log                     global\n"
    config_content+="    mode                    $frontend_mode_override\n"
    config_content+="    option                  "
    if [[ "$frontend_mode_override" == "http" ]]; then
        config_content+="httplog\n"
    else
        config_content+="tcplog\n"
    fi
    config_content+="    option                  dontlognull\n"
    config_content+="    timeout connect         5s\n"
    config_content+="    timeout client          50s\n"
    config_content+="    timeout server          50s\n"
    config_content+="\n"

    config_content+="frontend dynamic_port_forwarder\n"
    config_content+="    mode $frontend_mode_override\n"

    local bind_lines=""
    local sorted_ports=()
    for p in "${!unique_frontend_ports_mode[@]}"; do
        sorted_ports+=("$p")
    done
    IFS=$'\n' sorted_ports=($(sort -n <<<"${sorted_ports[*]}"))
    unset IFS

    if [[ ${#sorted_ports[@]} -gt 0 ]]; then
        for port in "${sorted_ports[@]}"; do
            bind_lines+="    bind *:${port}\n"
        done
    else
        bind_lines="    bind *:8080 # Default bind if no tunnels are configured\n"
    fi
    config_content+="$bind_lines"
    config_content+="\n"

    local acl_rules=""
    local use_backend_rules=""
    local backends_config=""
    local backend_counter=0

    # Define a maximum number of ports per ACL to avoid 'too many words'
    local MAX_PORTS_PER_ACL=10 # Reduced to 10 for more safety

    for tunnel_str in "${TUNNELS[@]}"; do
        local backend_ip=$(echo "$tunnel_str" | grep -o '"backend_ip":"[^"]*"' | cut -d: -f2 | tr -d '"')
        local ports=$(echo "$tunnel_str" | grep -o '"ports":"[^"]*"' | cut -d: -f2 | tr -d '"')
        local mode=$(echo "$tunnel_str" | grep -o '"mode":"[^"]*"' | cut -d: -f2 | tr -d '"')

        if [[ -z "$backend_ip" || -z "$ports" ]]; then
            continue
        fi

        IFS=',' read -ra current_ports_array <<< "$ports"
        IFS=',' read -ra backend_ips_array <<< "$backend_ip"

        # Shorten backend name to avoid 'too many words'
        local backend_name="be_${backend_counter}" 

        backends_config+="\nbackend ${backend_name}\n"
        backends_config+="    mode ${mode}\n"

        local health_check_cmd=""
        if [[ -n "$HEALTH_CHECK_PORT" ]]; then
            if [[ "$mode" == "http" ]]; then
                health_check_cmd="httpchk GET /"
            else
                health_check_cmd="check port ${HEALTH_CHECK_PORT}"
            fi
        fi

        local health_check_line_for_backend=""
        if [[ "$mode" == "tcp" ]]; then
            health_check_line_for_backend="    option tcp-check # Enable basic TCP connection checks\n"
            if [[ -n "$HEALTH_CHECK_PORT" ]]; then # Only add explicit health check if specified
                health_check_line_for_backend+="    ${health_check_cmd}\n"
            fi
        elif [[ "$mode" == "http" && -n "$HEALTH_CHECK_PORT" ]]; then # HTTP global health check, add to backend
            health_check_line_for_backend="    ${health_check_cmd}\n"
        fi

        if [[ ${#backend_ips_array[@]} -gt 1 ]]; then
            backends_config+="    balance roundrobin # Load balancing for multiple servers\n"
        fi

        for i in "${!backend_ips_array[@]}"; do
            local ip="${backend_ips_array[$i]}"
            local server_health_check_part=""
            # --- IMPORTANT FIX HERE: Removed %[dst_port] from the IP part ---
            # HAProxy handles dynamic port mapping implicitly in tcp mode,
            # or requires specific 'use-server' rules with 'map' for http/tcp modes.
            # For a direct passthrough, just specifying IP is enough,
            # or if the backend port is fixed, add it: ${ip}:<fixed_port>
            # Since user wants dynamic, we assume backend port is same as frontend.
            # If a fixed port is needed, that logic must be added.
            if [[ "$mode" == "http" && -n "$HEALTH_CHECK_PORT" ]]; then
                server_health_check_part="${health_check_cmd}"
            elif [[ "$mode" == "tcp" && -n "$HEALTH_CHECK_PORT" ]]; then
                server_health_check_part="${health_check_cmd}"
            fi
            # The most common way to do this if the backend expects the same port as frontend:
            # For TCP, HAProxy generally forwards to the same port on the backend IP
            # For HTTP, it will connect to a default port (like 80 or 443) or the port specified in the 'server' line.
            # If the backend truly listens on dynamic ports matching frontend,
            # this simplest form is often used, or advanced 'map' functions.
            # Let's assume for now, it's about connecting to the IP,
            # and the health check part is separate.
            # If *all* listed ports for this tunnel forward to a *single* fixed port on the backend,
            # that fixed port needs to be requested from the user.
            # Given the previous context, "%[dst_port]" was an attempt to make it dynamic.
            # Let's simplify: HAProxy in TCP mode will send to the same port by default if no port is specified on server.
            # This is often the case for transparent proxying.
            # If a specific port *is* required, the script needs to ask for it.
            # For now, let's remove the problematic %[dst_port] from the server definition.
            # The health check portion remains on the line.
            # If the backend always listens on the *same* port as the frontend, just use the IP.
            # Otherwise, the user needs to provide a backend port.
            # For now, we'll assume the simple case of just the IP, expecting default TCP forwarding.
            backends_config+="    server srv${i} ${ip} ${server_health_check_part}\n"
        done
        if [[ -n "$health_check_line_for_backend" ]]; then
            backends_config+="$health_check_line_for_backend"
        fi

        # --- MODIFIED ACL GENERATION FOR LARGE NUMBER OF PORTS ---
        # Break down port list into multiple ACLs if it's too long
        local current_acl_group_conditions=""
        local group_index=0
        local ports_in_current_group=0
        local temp_port_list=""

        for p in "${current_ports_array[@]}"; do
            temp_port_list+=" $p"
            ((ports_in_current_group++))

            if (( ports_in_current_group >= MAX_PORTS_PER_ACL )); then
                local group_acl_name="p${backend_counter}g${group_index}" # Shorter ACL name
                acl_rules+="    acl ${group_acl_name} dst_port${temp_port_list}\n"
                if [[ -z "$current_acl_group_conditions" ]]; then
                    current_acl_group_conditions="${group_acl_name}"
                else
                    current_acl_group_conditions="${current_acl_group_conditions} or ${group_acl_name}"
                fi
                temp_port_list=""
                ports_in_current_group=0
                ((group_index++))
            fi
        done

        # Add any remaining ports in the last group
        if [[ -n "$temp_port_list" ]]; then
            local group_acl_name="p${backend_counter}g${group_index}" # Shorter ACL name
            acl_rules+="    acl ${group_acl_name} dst_port${temp_port_list}\n"
            if [[ -z "$current_acl_group_conditions" ]]; then
                current_acl_group_conditions="${group_acl_name}"
            else
                current_acl_group_conditions="${current_acl_group_conditions} or ${group_acl_name}"
            fi
        fi
        
        # Use the combined ACL group conditions in the use_backend rule
        use_backend_rules+="    use_backend ${backend_name} if ${current_acl_group_conditions}\n"
        
        ((backend_counter++))
    done

    config_content+="$acl_rules"
    config_content+="$use_backend_rules"
    config_content+="    default_backend default_drop_backend\n"
    config_content+="$backends_config"

    config_content+="\n" # Ensure newline before final backend
    config_content+="backend default_drop_backend\n"
    config_content+="    mode tcp\n"
    config_content+="    # This backend simply drops unmatched traffic.\n"
    config_content+="\n" # Ensure final newline

    echo -e "$config_content" > "$HAPROXY_TEMP_CONFIG" # Use -e for interpreting backslashes as newlines

    # Validate HAProxy config
    info_msg "Validating generated HAProxy configuration..."
    sudo haproxy -c -f "$HAPROXY_TEMP_CONFIG"
    if [[ $? -ne 0 ]]; then
        error_exit "HAProxy configuration validation failed! Check the output above."
        return 1 # Indicate failure
    fi
    success_msg "HAProxy configuration validated successfully."
    return 0 # Indicate success
}

apply_haproxy_config() {
    info_msg "Applying HAProxy configuration and restarting service..."

    # Generate config first
    generate_haproxy_config || return 1 # Exit function if config generation fails

    sudo cp "$HAPROXY_TEMP_CONFIG" "$HAPROXY_CONFIG_PATH" || error_exit "Failed to copy HAProxy configuration."
    sudo systemctl restart haproxy || error_exit "Failed to restart HAProxy service. Check 'sudo journalctl -u haproxy -f' for details."
    success_msg "HAProxy configuration applied and service restarted successfully."
    return 0 # Indicate success
}

show_haproxy_status() {
    echo -e "\n${CYAN}--- HAProxy Service Status ---${NC}"
    sudo systemctl status haproxy --no-pager
    echo "------------------------------"
}

# --- Main CLI Menu Functions ---

list_tunnels() {
    if [[ ${#TUNNELS[@]} -eq 0 ]]; then
        info_msg "No tunnels configured yet."
        return
    fi
    echo -e "\n${CYAN}--- Current Tunnels ---${NC}"
    for i in "${!TUNNELS[@]}"; do
        local tunnel_str="${TUNNELS[$i]}"
        # Extract values safely using string manipulation with grep/cut/tr
        local backend_ip=$(echo "$tunnel_str" | grep -o '"backend_ip":"[^"]*"' | cut -d: -f2 | tr -d '"')
        local ports=$(echo "$tunnel_str" | grep -o '"ports":"[^"]*"' | cut -d: -f2 | tr -d '"')
        local mode=$(echo "$tunnel_str" | grep -o '"mode":"[^"]*"' | cut -d: -f2 | tr -d '"')

        echo -e "${BOLD}ID: $i${NORMAL}"
        echo "  Backend IP(s): $backend_ip"
        echo "  Ports: $ports"
        echo "  Mode: $mode"
        echo "--------------------"
    done
    echo "Default Health Check Port: ${HEALTH_CHECK_PORT:-None}"
}

add_tunnel() {
    echo -e "\n${CYAN}--- Add New Tunnel ---${NC}"
    local backend_ip_val=$(get_user_input "Enter Backend IP(s) (comma-separated, e.g., 192.168.1.10,192.168.1.11)" "" "validate_ip" "Invalid IP format. Use comma-separated IPs like 192.168.1.1,192.168.1.2.")
    if [[ -z "$backend_ip_val" ]]; then warn_msg "Cancelled."; return; fi

    local ports_val=$(get_user_input "Enter Ports (comma-separated, e.g., 80,443,2222)" "" "validate_ports" "Invalid port format. Use comma-separated numbers like 80,443. Ports must be between 1 and 65535.")
    if [[ -z "$ports_val" ]]; then warn_msg "Cancelled."; return; fi
    
    local mode_val=""
    while true; do
        read -rp "Enter Mode (tcp/http, default: tcp): " mode_input
        mode_input="${mode_input,,}" # Convert to lowercase
        if [[ -z "$mode_input" ]]; then
            mode_val="tcp"
            break
        elif [[ "$mode_input" == "tcp" || "$mode_input" == "http" ]]; then
            mode_val="$mode_input"
            break
        else
            echo -e "${RED}Invalid mode. Enter 'tcp' or 'http'.${NC}"
        fi
    done

    # Store as a simple JSON string to easily parse attributes later
    local new_tunnel_json="{\"backend_ip\":\"$backend_ip_val\",\"ports\":\"$ports_val\",\"mode\":\"$mode_val\"}"
    TUNNELS+=("$new_tunnel_json")
    save_data
    success_msg "Tunnel added successfully."
    
    # Auto-apply and show status
    if apply_haproxy_config; then
        show_haproxy_status
    fi
}

edit_tunnel() {
    list_tunnels
    if [[ ${#TUNNELS[@]} -eq 0 ]]; then
        return
    fi

    local tunnel_id=""
    while true; do
        read -rp "Enter ID of tunnel to edit (or leave empty to cancel): " tunnel_id
        if [[ -z "$tunnel_id" ]]; then
            return # Go back to main menu
        fi
        if ! [[ "$tunnel_id" =~ ^[0-9]+$ ]] || (( tunnel_id < 0 || tunnel_id >= ${#TUNNELS[@]} )); then
            echo -e "${RED}Invalid tunnel ID.${NC}"
        else
            break
        fi
    done

    local tunnel_str="${TUNNELS[$tunnel_id]}"
    local current_backend_ip=$(echo "$tunnel_str" | grep -o '"backend_ip":"[^"]*"' | cut -d: -f2 | tr -d '"')
    local current_ports=$(echo "$tunnel_str" | grep -o '"ports":"[^"]*"' | cut -d: -f2 | tr -d '"')
    local current_mode=$(echo "$tunnel_str" | grep -o '"mode":"[^"]*"' | cut -d: -f2 | tr -d '"')

    echo -e "\n${CYAN}--- Editing Tunnel ID: ${tunnel_id} ---${NC}"
    local new_backend_ip=$(get_user_input "Enter new Backend IP(s)" "$current_backend_ip" "validate_ip" "Invalid IP format.")
    if [[ -z "$new_backend_ip" ]]; then warn_msg "Cancelled."; return; fi

    local new_ports=$(get_user_input "Enter new Ports" "$current_ports" "validate_ports" "Invalid port format.")
    if [[ -z "$new_ports" ]]; then warn_msg "Cancelled."; return; fi
    
    local new_mode_val=""
    while true; do
        read -rp "Enter new Mode (tcp/http, current: $current_mode): " new_mode_input
        new_mode_input="${new_mode_input,,}" # Corrected here: changed ==, to ,,
        if [[ -z "$new_mode_input" ]]; then
            new_mode_val="$current_mode"
            break
        elif [[ "$new_mode_input" == "tcp" || "$new_mode_input" == "http" ]]; then
            new_mode_val="$new_mode_input"
            break
        else
            echo -e "${RED}Invalid mode. Enter 'tcp' or 'http'.${NC}"
        fi
    done

    local updated_tunnel_json="{\"backend_ip\":\"$new_backend_ip\",\"ports\":\"$new_ports\",\"mode\":\"$new_mode_val\"}"
    TUNNELS[$tunnel_id]="$updated_tunnel_json"
    save_data
    success_msg "Tunnel updated successfully."

    # Auto-apply and show status
    if apply_haproxy_config; then
        show_haproxy_status
    fi
}

delete_tunnel() {
    list_tunnels
    if [[ ${#TUNNELS[@]} -eq 0 ]]; then
        return
    fi

    local tunnel_id=""
    while true; do
        read -rp "Enter ID of tunnel to delete (or leave empty to cancel): " tunnel_id
        if [[ -z "$tunnel_id" ]]; then
            return # Go back to main menu
        fi
        if ! [[ "$tunnel_id" =~ ^[0-9]+$ ]] || (( tunnel_id < 0 || tunnel_id >= ${#TUNNELS[@]} )); then
            echo -e "${RED}Invalid tunnel ID.${NC}"
        else
            break
        fi
    done

    read -rp "Are you sure you want to delete tunnel ID ${tunnel_id}? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # Remove element from array by creating a new array without the deleted item
        local temp_tunnels=()
        for i in "${!TUNNELS[@]}"; do
            if [[ "$i" -ne "$tunnel_id" ]]; then
                temp_tunnels+=("${TUNNELS[$i]}")
            fi
        done
        TUNNELS=("${temp_tunnels[@]}")
        save_data
        success_msg "Tunnel deleted successfully."
        
        # Auto-apply and show status
        if apply_haproxy_config; then
            show_haproxy_status
        fi
    else
        info_msg "Deletion cancelled."
    fi
}

manage_health_check_port() {
    echo -e "\n${CYAN}--- Manage Default Health Check Port ---${NC}"
    local new_port_val=$(get_user_input "Enter fixed default port for TCP health checks (e.g., 80, 22). Leave empty to disable." "$HEALTH_CHECK_PORT" "validate_ports" "Invalid port. Must be a number between 1 and 65535 or empty.")
    HEALTH_CHECK_PORT="$new_port_val"
    save_data
    success_msg "Default health check port updated."

    # Auto-apply and show status
    if apply_haproxy_config; then
        show_haproxy_status
    fi
}

# --- Main Menu ---

main_menu() {
    # Check for HAProxy installation at start
    if ! command -v haproxy &> /dev/null; then
        info_msg "HAProxy is not installed. Attempting to install..."
        sudo apt update && sudo apt install -y haproxy
        if [[ $? -ne 0 ]]; then
            error_exit "Failed to install HAProxy. Please install it manually or check your internet connection."
            return 1 # Exit main menu if HAProxy cannot be installed
        fi
        success_msg "HAProxy installed successfully."
    fi

    load_data # Load data when script starts

    while true; do
        echo -e "\n${BOLD}${PURPLE}--- HAProxy Tunnel Manager (Bash CLI) ---${NORMAL}${NC}"
        echo -e "1. ${GREEN}List Tunnels${NC}"
        echo -e "2. ${GREEN}Add New Tunnel${NC}"
        echo -e "3. ${GREEN}Edit Tunnel${NC}"
        echo -e "4. ${GREEN}Delete Tunnel${NC}"
        echo -e "5. ${GREEN}Manage Default Health Check Port${NC}"
        echo -e "6. ${GREEN}Apply HAProxy Configuration & Restart Service (Manual Trigger)${NC}" # Renamed for clarity
        echo -e "7. ${YELLOW}Show HAProxy Service Status${NC}" # New option for status
        echo -e "8. ${RED}Exit${NC}" # Increased exit option
        
        read -rp "${BOLD}Enter your choice (1-8): ${NORMAL}" choice

        case "$choice" in
            1) list_tunnels ;;
            2) add_tunnel ;; # Now calls apply_haproxy_config and show_haproxy_status internally
            3) edit_tunnel ;; # Now calls apply_haproxy_config and show_haproxy_status internally
            4) delete_tunnel ;; # Now calls apply_haproxy_config and show_haproxy_status internally
            5) manage_health_check_port ;; # Now calls apply_haproxy_config and show_haproxy_status internally
            6) apply_haproxy_config && show_haproxy_status ;; # Manual apply/restart, then show status
            7) show_haproxy_status ;; # Only show status
            8)
                info_msg "Exiting..."
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter a number between 1 and 8.${NC}"
                ;;
        esac
    done
}

# --- Script Entry Point ---
main_menu
