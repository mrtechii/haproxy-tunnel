#!/bin/bash
# ==========================================================
# === HAProxy Dynamic Port Forwarding Manager (Bash-Only) ===
# ==========================================================
# --- Configuration & File Paths ---
HAPROXY_CONFIG_PATH="/etc/haproxy/haproxy.cfg"
HAPROXY_TEMP_CONFIG="/tmp/haproxy_generated.cfg" # Temporary file for validation before deployment
JOURNALD_CONFIG_PATH="/etc/systemd/journald.conf" # Path to journald configuration file

SCRIPT_DIR="/root/"
mkdir -p "$SCRIPT_DIR"

# Get the full path and directory of the currently executing bash script
# Using readlink -f to resolve symlinks and get the absolute path
BASH_SCRIPT_FULL_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$BASH_SCRIPT_FULL_PATH")" # This will be /root/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.haproxy_tunnels_data"

DATA_FILE="${SCRIPT_DIR}/.haproxy_tunnels_data" # Hidden file in script's directory (e.g., /root/.haproxy_tunnels_data)
PYTHON_BOT_SCRIPT_PATH="${SCRIPT_DIR}/haproxy_telegram_bot.py" # Python script in the same directory as bash script
SYSTEMD_SERVICE_FILE="/etc/systemd/system/haproxy-tunnel-bot.service" # Systemd service file path

# --- ANSI Color Codes (Added Bold to all) ---
# Using $'...' syntax for robustness in read -rp
BLACK=$'\033[1;30m'
RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
ORANGE=$'\033[1;38;5;208m'
BLUE=$'\033[1;34m'
MAGENTA=$'\033[1;35m'
CYAN=$'\033[1;36m'
LIGHT_CYAN=$'\033[1;96m'
WHITE=$'\033[1;37m'
PINK=$'\033[1;38;5;163m'

BRIGHT_RED=$'\033[1;91m'
BRIGHT_GREEN=$'\033[1;92m'
BRIGHT_YELLOW=$'\033[1;30m'
BRIGHT_BLUE=$'\033[1;94m'
BRIGHT_MAGENTA=$'\033[1;95m'
BRIGHT_WHITE=$'\033[1;97m'

NC=$'\033[0m' # No Color / Reset

# --- Utility Functions for Colored Messages ---

error_msg() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo -e "${BRIGHT_RED}Error:${NC} $1" >&2
    else
        echo "Error: $1" >&2
    fi
    return 1
}

success_msg() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo -e "${BRIGHT_GREEN}Success:${NC} $1"
    fi
}

info_msg() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo -e "${CYAN}Info:${NC} $1"
    fi
}

warn_msg() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo -e "${YELLOW}Warning:${NC} $1"
    fi
}

# --- Dependency Check and Installation ---
check_dependencies() {
    info_msg "Checking for required dependencies..."

    local install_needed=false
    local missing_packages=""

    # Check for jq
    if ! command -v jq &>/dev/null; then
        warn_msg "'jq' is not installed. It is required for the Telegram bot to function correctly."
        missing_packages+="jq "
        install_needed=true
    fi

    # Check for python3
    if ! command -v python3 &>/dev/null; then
        warn_msg "'python3' is not installed. It is required for the Telegram bot."
        missing_packages+="python3 "
        install_needed=true
    fi

    # Check for python3-pip
    if ! command -v pip3 &>/dev/null; then
        warn_msg "'pip3' is not installed. It is required to install Python libraries."
        missing_packages+="python3-pip "
        install_needed=true
    fi

    if [[ "$install_needed" == "true" ]]; then
        info_msg "Installing missing system packages: ${missing_packages}..."
        sudo apt update
        sudo apt install -y $missing_packages || { error_msg "Failed to install required system packages. Please install them manually and try again."; return 1; }
        success_msg "System packages installed."
    else
        info_msg "All system dependencies (jq, python3, pip3) are installed."
    fi

    # Check for python-telegram-bot
    if ! python3 -c "import telegram" &>/dev/null; then
        pip3 install python-telegram-bot==20.6
        warn_msg "'python-telegram-bot' library is not installed for Python3."
        info_msg "Installing 'python-telegram-bot'..."
        pip3 install python-telegram-bot || { error_msg "Failed to install 'python-telegram-bot'. Ensure pip is working and network is available."; return 1; }
        success_msg "'python-telegram-bot' installed."
    else
        info_msg "'python-telegram-bot' library is installed."
    fi

    return 0
}

# --- Data Persistence Functions ---

load_data() {
    TUNNELS=() # Clear existing tunnels
    HEALTH_CHECK_PORT="" # Clear existing port
    TELEGRAM_BOT_TOKEN="" # Clear existing bot token
    TELEGRAM_ADMIN_ID="" # Clear existing admin ID

    if [[ -f "$DATA_FILE" ]]; then
        if [[ "$INTERACTIVE_MODE" == "true" ]]; then
            info_msg "Loading configuration from ${CYAN}${DATA_FILE}${NC}..."
        fi

        HEALTH_CHECK_PORT=$(grep '^HEALTH_CHECK_PORT=' "$DATA_FILE" | cut -d= -f2- | head -n 1)
        TELEGRAM_BOT_TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$DATA_FILE" | cut -d= -f2- | head -n 1)
        TELEGRAM_ADMIN_ID=$(grep '^TELEGRAM_ADMIN_ID=' "$DATA_FILE" | cut -d= -f2- | head -n 1)

        if [[ -z "$HEALTH_CHECK_PORT" ]]; then
            HEALTH_CHECK_PORT="" # Ensure it's empty if not found
        fi
        if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
            TELEGRAM_BOT_TOKEN="" # Ensure it's empty if not found
        fi
        if [[ -z "$TELEGRAM_ADMIN_ID" ]]; then
            TELEGRAM_ADMIN_ID="" # Ensure it's empty if not found
        fi

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
        if [[ "$INTERACTIVE_MODE" == "true" ]]; then
            success_msg "Configuration loaded."
        fi
    else
        if [[ "$INTERACTIVE_MODE" == "true" ]]; then
            warn_msg "Data file '${CYAN}${DATA_FILE}${NC}' not found. Starting with empty configuration."
        fi
    fi
}

save_data() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        info_msg "Saving configuration to ${CYAN}${DATA_FILE}${NC}..."
    fi
    > "$DATA_FILE"

    echo "HEALTH_CHECK_PORT=$HEALTH_CHECK_PORT" >> "$DATA_FILE"
    echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" >> "$DATA_FILE"
    echo "TELEGRAM_ADMIN_ID=$TELEGRAM_ADMIN_ID" >> "$DATA_FILE"

    for tunnel_str in "${TUNNELS[@]}"; do
        echo "TUNNEL_START" >> "$DATA_FILE"
        echo "$tunnel_str" >> "$DATA_FILE"
        echo "TUNNEL_END" >> "$DATA_FILE"
    done
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        success_msg "Configuration saved."
    fi
}

# --- Validation Functions ---

is_valid_single_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet < 0 || octet > 255 )); then return 1; fi
        done
        return 0
    fi

    if [[ "$ip" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]]; then return 0; fi
    if [[ "$ip" =~ ^([0-9a-fA-F]{1,4}(:[0-9a-fA-F]{0,4})?)::([0-9a-fA-F]{1,4}(:[0-9a-fA-F]{0,4})?)?$ ]]; then
        if [[ "$(echo "$ip" | grep -o '::' | wc -l)" -le 1 ]]; then return 0; fi
    fi
    if [[ "$ip" =~ ^([0-9a-fA-F]{1,4}:){6}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; then return 0; fi

    return 1
}

validate_ip() {
    local ips_str="$1"
    IFS=',' read -r -a ADDR <<< "$ips_str"
    for i in "${ADDR[@]}"; do
        if ! is_valid_single_ip "${i//[\[\]]/}"; then
            return 1
        fi
    done
    return 0
}

validate_ports() {
    local ports_str="$1"
    IFS=',' read -r -a PORTS <<< "$ports_str"
    for p in "${PORTS[@]}"; do
        if ! [[ "$p" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then
            return 1
        fi
    done
    return 0
}

is_valid_telegram_id() {
    local id="$1"
    if [[ "$id" =~ ^-?[0-9]+$ ]]; then
        return 0
    fi
    return 1
}


# --- User Input Functions ---

get_user_input() {
    local prompt_text="$1"
    local current_value="$2"
    local validation_func="$3"
    local error_message="$4"
    local result=""

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        while true; do
            local display_prompt="${prompt_text}";
            if [[ -n "$current_value" ]]; then
                display_prompt+=" (Current: ${current_value})"
            fi
            read -rp "${BRIGHT_YELLOW}${display_prompt}:${NC} " user_input_val
            user_input_val="${user_input_val// /}" # Remove spaces

            if [[ -z "$user_input_val" ]]; then # If user just pressed Enter
                result="$current_value"
                break
            fi

            if [[ -z "$validation_func" ]]; then
                result="$user_input_val"
                break
            elif "$validation_func" "${user_input_val}"; then
                result="$user_input_val"
                break
            else
                error_msg "${error_message:-Invalid input. Please try again.}"
            fi
        done
        echo "$result"
    else
        # In non-interactive mode, directly return the provided value
        # This part assumes validation is done by the caller in non-interactive mode.
        echo "$current_value"
    fi
}

format_ip_for_haproxy() {
    local ip="$1"
    if [[ "$ip" =~ ":" ]] && [[ ! "$ip" =~ ^\[.*\]$ ]]; then
        echo "[$ip]"
    else
        echo "$ip"
    fi
}

# --- HAProxy Configuration Generation ---

generate_haproxy_config() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        info_msg "Generating HAProxy configuration..."
    fi
    local config_content=""

    config_content+="global\n"
    config_content+="    log /dev/log         local0\n"
    config_content+="    chroot /var/lib/haproxy\n"
    config_content+="    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners\n"
    config_content+="    stats timeout 30s\n"
    config_content+="    user haproxy\n"
    config_content+="    group haproxy\n"
    config_content+="    daemon\n"
    config_content+="    maxconn 20000\n"
    config_content+="\n"

    config_content+="defaults\n"
    config_content+="    log                  global\n"
    config_content+="    option               dontlog-normal\n"
    config_content+="    timeout connect 5s\n"
    config_content+="    timeout client  50s\n"
    config_content+="    timeout server  50s\n"
    config_content+="\n"

    local listen_sections_config="" tunnel_counter=0
    for tunnel_str in "${TUNNELS[@]}"; do
        local backend_ip_list_raw=$(echo "$tunnel_str" | sed -n 's/.*"backend_ip":"\([^"]*\)".*/\1/p')
        local ports_raw=$(echo "$tunnel_str" | sed -n 's/.*"ports":"\([^"]*\)".*/\1/p')
        local mode=$(echo "$tunnel_str" | sed -n 's/.*"mode":"\([^"]*\)".*/\1/p')

        if [[ -z "$backend_ip_list_raw" || -z "$ports_raw" ]]; then continue; fi

        # Ensure mode is never empty for HAProxy, default to tcp if it is
        if [[ -z "$mode" ]]; then
            mode="tcp"
        fi

        IFS=',' read -r -a current_ports_array <<< "$ports_raw"
        IFS=',' read -r -a backend_ips_array <<< "$backend_ip_list_raw"

        for p in "${current_ports_array[@]}"; do
            local listen_name="listen_tunnel_${tunnel_counter}_port_${p}"
            listen_sections_config+="\nlisten ${listen_name}\n"
            listen_sections_config+="    bind *:${p}\n"
            listen_sections_config+="    mode ${mode} # DEBUG_MODE: '$mode'\n"

            if [[ "$mode" == "http" ]]; then
                listen_sections_config+="    option               httplog\n"
            else
                listen_sections_config+="    option               tcplog\n"
            fi
            listen_sections_config+="    option               dontlognull\n"

            local health_check_options=""
            local target_backend_port_for_service="${p}"

            if [[ -n "$HEALTH_CHECK_PORT" ]]; then
                if [[ "$HEALTH_CHECK_PORT" == "none" ]]; then
                    health_check_options=""
                elif [[ "$mode" == "http" ]]; then
                    health_check_options+="    option httpchk GET / HTTP/1.1\n"
                    health_check_options+="    http-check expect status 200\n"
                else
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

    config_content+="\nbackend default_drop_backend\n"
    config_content+="    mode tcp\n"
    config_content+="    # This backend simply drops unmatched traffic if no other rules apply.\n"
    config_content+="\n"

    echo -e "$config_content" > "$HAPROXY_TEMP_CONFIG"

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        info_msg "Validating generated HAProxy configuration..."
    fi
    sudo haproxy -c -V -f "$HAPROXY_TEMP_CONFIG"
    if [[ $? -ne 0 ]]; then
        error_msg "HAProxy configuration validation failed! Check the output above."
        return 1
    fi
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        success_msg "HAProxy configuration validated successfully."
    fi
    return 0
}

apply_haproxy_config() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        info_msg "Applying HAProxy configuration and restarting service..."
    fi

    generate_haproxy_config || return 1

    sudo cp "$HAPROXY_TEMP_CONFIG" "$HAPROXY_CONFIG_PATH" || \
        { error_msg "Failed to copy HAProxy configuration to ${CYAN}${HAPROXY_CONFIG_PATH}${NC}. Do you have root permissions?"; return 1; }

    sudo systemctl restart haproxy || \
        { error_msg "Failed to restart HAProxy service. Check 'sudo journalctl -u haproxy -f' for details."; return 1; }

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        success_msg "HAProxy configuration applied and service restarted successfully."
    fi
    return 0
}

show_haproxy_status() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo -e "\n${BRIGHT_BLUE}--- HAProxy Service Status ---${NC}"
        sudo systemctl status haproxy --no-pager
        echo -e "${BRIGHT_BLUE}------------------------------${NC}"
    else
        sudo systemctl is-active haproxy &>/dev/null && echo "active" || echo "inactive"
    fi
}

# --- Journald Configuration Function ---
configure_journald_for_logs() {
    info_msg "Configuring systemd-journald to reduce terminal log spam..."

    if [[ ! -f "$JOURNALD_CONFIG_PATH" ]]; then
        error_msg "Journald config file not found at ${CYAN}${JOURNALD_CONFIG_PATH}${NC}. Cannot configure log levels."
        return 1
    fi

    sudo cp "$JOURNALD_CONFIG_PATH" "${JOURNALD_CONFIG_PATH}.bak"
    info_msg "Backed up ${CYAN}${JOURNALD_CONFIG_PATH}${NC} to ${CYAN}${JOURNALD_CONFIG_PATH}.bak${NC}."

    if grep -qE '^\s*#?\s*ForwardToWall=' "$JOURNALD_CONFIG_PATH"; then
        sudo sed -i -E 's/^\s*#?\s*ForwardToWall=.*/ForwardToWall=no/' "$JOURNALD_CONFIG_PATH"
        info_msg "Updated 'ForwardToWall=no' in journald.conf."
    else
        echo "ForwardToWall=no" | sudo tee -a "$JOURNALD_CONFIG_PATH" > /dev/null
        info_msg "Added 'ForwardToWall=no' to journald.conf."
    fi

    if grep -qE '^\s*#?\s*MaxLevelWall=' "$JOURNALD_CONFIG_PATH"; then
        sudo sed -i -E 's/^\s*#?\s*MaxLevelWall=.*/MaxLevelWall=emerg/' "$JOURNALD_CONFIG_PATH"
        info_msg "Updated 'MaxLevelWall=emerg' in journald.conf."
    else
        echo "MaxLevelWall=emerg" | sudo tee -a "$JOURNALD_CONFIG_PATH" > /dev/null
        info_msg "Added 'MaxLevelWall=emerg' to journald.conf."
    fi

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
    if [[ "$INTERACTIVE_MODE" == "false" ]]; then
        load_data
    fi

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo -e "\n${BRIGHT_BLUE}--- Current Tunnels ---${NC}"
        if [[ ${#TUNNELS[@]} -eq 0 ]]; then
            info_msg "No tunnels configured yet."
            echo -e "${BRIGHT_BLUE}-----------------------${NC}"
            return
        fi
        for i in "${!TUNNELS[@]}"; do
            local tunnel_str="${TUNNELS[$i]}"
            local backend_ip=$(echo "$tunnel_str" | sed -n 's/.*"backend_ip":"\([^"]*\)".*/\1/p')
            local ports=$(echo "$tunnel_str" | sed -n 's/.*"ports":"\([^"]*\)".*/\1/p')
            local mode=$(echo "$tunnel_str" | sed -n 's/.*"mode":"\([^"]*\)".*/\1/p')

            echo -e "${CYAN}ID: $i${NC}"
            echo -e "  ${YELLOW}Backend IP(s):${NC} ${BRIGHT_GREEN}$backend_ip${NC}"
            echo -e "  ${YELLOW}Ports: ${NC}${BRIGHT_GREEN}$ports${NC}"
            echo -e "  ${YELLOW}Mode: ${NC}${BRIGHT_GREEN}${mode:-tcp}${NC}" # Display default if empty
            echo -e "${BRIGHT_BLUE}--------------------${NC}"
        done
        echo -e "${BRIGHT_BLUE}Default Health Check Port: ${BRIGHT_GREEN}${HEALTH_CHECK_PORT:-None}${NC}"
        echo -e "${BRIGHT_BLUE}-----------------------${NC}"
    else
        local json_output="["
        local first=true
        for i in "${!TUNNELS[@]}"; do
            local tunnel_str="${TUNNELS[$i]}"
            local backend_ip=$(echo "$tunnel_str" | jq -r '.backend_ip // ""')
            local ports=$(echo "$tunnel_str" | jq -r '.ports // ""')
            local mode=$(echo "$tunnel_str" | jq -r '.mode // ""')

            backend_ip=${backend_ip:-""}
            ports=${ports:-""}
            mode=${mode:-"tcp"} # Always output tcp if mode is empty for JSON output

            if [[ "$first" = false ]]; then
                json_output+=","
            fi
            local escaped_backend_ip=$(printf %s "$backend_ip" | sed 's/"/\\"/g')
            local escaped_ports=$(printf %s "$ports" | sed 's/"/\\"/g')
            local escaped_mode=$(printf %s "$mode" | sed 's/"/\\"/g')

            json_output+="{ \"id\": $i, \"backend_ip\": \"$escaped_backend_ip\", \"ports\": \"$escaped_ports\", \"mode\": \"$escaped_mode\" }"
            first=false
        done
        json_output+="]"
        local escaped_health_check_port=$(printf %s "$HEALTH_CHECK_PORT" | sed 's/"/\\"/g')
        echo "{\"tunnels\": $json_output, \"health_check_port\": \"$escaped_health_check_port\"}"
    fi
}

add_tunnel() {
    local backend_ip_val="$1"
    local ports_val="$2"
    local mode_val="$3"

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        info_msg "Adding a new tunnel."
        backend_ip_val=$(get_user_input "Enter backend IP(s) (comma-separated, e.g., 1.1.1.1,2.2.2.2 or [::1])" "" validate_ip "Invalid IP format.") || return 1
        ports_val=$(get_user_input "Enter ports (comma-separated, e.g., 80,443)" "" validate_ports "Invalid port(s). Must be numbers between 1 and 65535.") || return 1        # Explicitly ensure "tcp" is the default displayed if user presses Enter
        mode_val=$(get_user_input "Enter mode (tcp or http)" "tcp" "[[ \"\${1,,}\" == \"tcp\" || \"\${1,,}\" == \"http\" ]]" "Invalid mode. Must be 'tcp' or 'http'.") || return 1

        # Explicitly ensure mode_val is 'tcp' if it's empty after user input
        if [[ -z "$mode_val" ]]; then
            mode_val="tcp"
        fi
    else
        # For non-interactive mode, ensure mode_val is not empty, default to tcp if it is.
        if [[ -z "$mode_val" ]]; then
            mode_val="tcp"
        fi

        if ! validate_ip "$backend_ip_val"; then error_msg "Invalid backend IP(s): $backend_ip_val"; return 1; fi
        if ! validate_ports "$ports_val"; then error_msg "Invalid port(s): $ports_val"; return 1; fi
        if [[ "${mode_val,,}" != "tcp" && "${mode_val,,}" != "http" ]]; then error_msg "Invalid mode: $mode_val. Must be 'tcp' or 'http'."; return 1; fi
    fi

    local new_tunnel="{\"backend_ip\":\"$backend_ip_val\",\"ports\":\"$ports_val\",\"mode\":\"${mode_val,,}\"}" # Ensure mode is lowercase
    TUNNELS+=("$new_tunnel")
    save_data
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        success_msg "Tunnel added."
    fi
    apply_haproxy_config
}

edit_tunnel() {
    local tunnel_id="$1"
    local new_backend_ip_val="$2"
    local new_ports_val="$3"
    local new_mode_val="$4"

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        list_tunnels
        info_msg "Editing an existing tunnel."
        read -rp "${BRIGHT_YELLOW}Enter the ID of the tunnel to edit:${NC} " tunnel_id
    fi

    if ! [[ "$tunnel_id" =~ ^[0-9]+$ ]] || (( tunnel_id < 0 || tunnel_id >= ${#TUNNELS[@]} )); then
        error_msg "Invalid tunnel ID: $tunnel_id"
        return 1
    fi

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        local current_tunnel_str="${TUNNELS[$tunnel_id]}"
        local current_backend_ip=$(echo "$current_tunnel_str" | sed -n 's/.*"backend_ip":"\([^"]*\)".*/\1/p')
        local current_ports=$(echo "$current_tunnel_str" | sed -n 's/.*"ports":"\([^"]*\)".*/\1/p')
        local current_mode=$(echo "$current_tunnel_str" | sed -n 's/.*"mode":"\([^"]*\)".*/\1/p')
        # If current_mode is empty (e.g., from old configs), default it to 'tcp' for the prompt
        local display_current_mode="${current_mode:-tcp}"

        new_backend_ip_val=$(get_user_input "Enter new backend IP(s)" "$current_backend_ip" validate_ip "Invalid IP format.") || return 1
        new_ports_val=$(get_user_input "Enter new ports" "$current_ports" validate_ports "Invalid port(s). Must be numbers between 1 and 65535.") || return 1
        new_mode_val=$(get_user_input "Enter new mode (tcp or http)" "$display_current_mode" "[[ \"\${1,,}\" == \"tcp\" || \"\${1,,}\" == \"http\" ]]" "Invalid mode. Must be 'tcp' or 'http'.") || return 1

        # Explicitly ensure new_mode_val is 'tcp' if it's empty after user input
        if [[ -z "$new_mode_val" ]]; then
            new_mode_val="tcp"
        fi
    else
        # For non-interactive mode, ensure new_mode_val is not empty, use current_mode if it is.
        local current_tunnel_str="${TUNNELS[$tunnel_id]}"
        local current_mode=$(echo "$current_tunnel_str" | sed -n 's/.*"mode":"\([^"]*\)".*/\1/p')
        if [[ -z "$new_mode_val" ]]; then
            new_mode_val="${current_mode:-tcp}" # Default to tcp if current_mode is also empty
        fi

        if ! validate_ip "$new_backend_ip_val"; then error_msg "Invalid new backend IP(s): $new_backend_ip_val"; return 1; fi
        if ! validate_ports "$new_ports_val"; then error_msg "Invalid new port(s): $new_ports_val"; return 1; fi
        if [[ "${new_mode_val,,}" != "tcp" && "${new_mode_val,,}" != "http" ]]; then error_msg "Invalid new mode: $new_mode_val. Must be 'tcp' or 'http'."; return 1; fi
    fi

    local updated_tunnel="{\"backend_ip\":\"$new_backend_ip_val\",\"ports\":\"$new_ports_val\",\"mode\":\"${new_mode_val,,}\"}" # Ensure mode is lowercase
    TUNNELS[$tunnel_id]="$updated_tunnel"
    save_data
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        success_msg "Tunnel ID $tunnel_id updated."
    fi
    apply_haproxy_config
}

delete_tunnel() {
    local tunnel_id="$1"

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        list_tunnels
        info_msg "Deleting a tunnel."
        read -rp "${BRIGHT_YELLOW}Enter the ID of the tunnel to delete:${NC} " tunnel_id
    fi

    if ! [[ "$tunnel_id" =~ ^[0-9]+$ ]] || (( tunnel_id < 0 || tunnel_id >= ${#TUNNELS[@]} )); then
        error_msg "Invalid tunnel ID: $tunnel_id"
        return 1
    fi

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        read -rp "${BRIGHT_RED}Are you sure you want to delete tunnel ID $tunnel_id? (y/N):${NC} " confirm
        if ! [[ "$confirm" =~ ^[yY]$ ]]; then
            warn_msg "Deletion cancelled."
            return 1
        fi
    fi
    
    if ! [[ "$tunnel_id" =~ ^[0-9]+$ ]]; then
           error_msg "Invalid tunnel ID: $tunnel_id"
           return 1
    fi

    unset 'TUNNELS[tunnel_id]'
    TUNNELS=("${TUNNELS[@]}")
    save_data
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        success_msg "Tunnel ID $tunnel_id deleted."
    fi
    apply_haproxy_config
}

manage_health_check_port() {
    local new_port="$1"

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        info_msg "Managing default Health Check Port."
        new_port=$(get_user_input "Enter the new Health Check Port (e.g., 80) or 'none' to disable" "$HEALTH_CHECK_PORT" "[[ \$1 == \"none\" || (\$1 =~ ^[0-9]+\$ && \$1 -ge 1 && \$1 -le 65535) ]]" "Invalid port. Enter a number between 1 and 65535 or 'none'.") || return 1
    else
        if [[ "$new_port" != "none" ]] && ! [[ "$new_port" =~ ^[0-9]+$ && "$new_port" -ge 1 && "$new_port" -le 65535 ]]; then
            error_msg "Invalid port: $new_port. Must be a number between 1 and 65535 or 'none'."
            return 1
        fi
    fi

    HEALTH_CHECK_PORT="$new_port"
    save_data
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        success_msg "Default Health Check Port set to: ${BRIGHT_GREEN}${HEALTH_CHECK_PORT:-None}${NC}"
    fi
    apply_haproxy_config
}

# --- Telegram Bot Management Functions ---

configure_telegram_bot() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        info_msg "Configuring Telegram Bot."
        local new_token=$(get_user_input "Enter your Telegram Bot Token" "$TELEGRAM_BOT_TOKEN") || return 1
        local new_admin_id=$(get_user_input "Enter your Telegram Admin User ID (numeric, e.g., 123456789). Leave empty for no admin restriction." "$TELEGRAM_ADMIN_ID" is_valid_telegram_id "Invalid Telegram User ID.") || { new_admin_id=""; }

        TELEGRAM_BOT_TOKEN="$new_token"
        TELEGRAM_ADMIN_ID="$new_admin_id"
        save_data
        success_msg "Telegram Bot Token and Admin ID saved. Remember to regenerate the service file."
    else
        error_msg "Cannot configure Telegram bot in non-interactive mode."
        return 1
    fi
}

create_bot_systemd_service() {
    info_msg "Generating Telegram Bot Systemd Service file and Python script..."

    cat << 'EOF' > "$PYTHON_BOT_SCRIPT_PATH"
#!/usr/bin/env python3
import os
import logging
import subprocess
import json
import re # Import regex module
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import Application, CommandHandler, ContextTypes, MessageHandler, filters, CallbackQueryHandler

# Configure logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Determine the path to the bash script relative to the python script
# This script (haproxy_telegram_bot.py) is assumed to be in the same directory as n.sh (or bash.sh)
# Use the environment variable passed by systemd, or default to './n.sh'
BASH_SCRIPT_PATH = os.environ.get('BASH_SCRIPT_PATH', './n.sh') 

# Load configuration from the bash script's data file
def load_bash_config():
    try:
        # Use --get-data to get JSON output directly from the bash script
        # The bash script is expected to print JSON to stdout
        cmd = [BASH_SCRIPT_PATH, '--get-data']
        logger.info(f"Loading config from bash script: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, encoding='utf-8')
        
        # Check if the output is empty or not valid JSON
        if not result.stdout.strip():
            logger.error(f"Bash script returned empty output for --get-data. Stderr: {result.stderr}")
            return '', '', [], '' # Return empty values for token, admin_id, tunnels, health_check_port
            
        # Attempt to load JSON. If it fails, log the raw output for debugging.
        try:
            config_data = json.loads(result.stdout.strip())
        except json.JSONDecodeError as e:
            logger.error(f"Error decoding JSON from bash script output: {e}. Raw output: '{result.stdout.strip()}'")
            return '', '', [], '' # Return empty values on JSON decode error

        # Extract token and admin ID from the top-level keys
        token = config_data.get('TELEGRAM_BOT_TOKEN', '')
        admin_id = config_data.get('TELEGRAM_ADMIN_ID', '')
        
        # Get raw tunnels data
        raw_tunnels_info = config_data.get('tunnels', [])
        processed_tunnels = []
        # Assign an 'id' (index) to each tunnel for easier management in the bot
        for i, tunnel_dict in enumerate(raw_tunnels_info):
            tunnel_dict['id'] = i  # Add 'id' based on its position
            processed_tunnels.append(tunnel_dict)

        health_check_port_info = config_data.get('HEALTH_CHECK_PORT', '') # Corrected key to match bash output
        
        return token, admin_id, processed_tunnels, health_check_port_info
    except subprocess.CalledProcessError as e:
        logger.error(f"Error loading bash config (subprocess error): {e.stderr}")
        return '', '', [], ''
    except Exception as e:
        logger.error(f"An unexpected error occurred while loading config: {e}")
        return '', '', [], ''

# Initial load of configuration
TELEGRAM_BOT_TOKEN, TELEGRAM_ADMIN_ID, _, _ = load_bash_config() 

if not TELEGRAM_BOT_TOKEN:
    logger.critical("Bot token not loaded. Please configure through the bash script.")
    import sys
    sys.exit(1) # Exit if token is not set to prevent continuous restarts

if not TELEGRAM_ADMIN_ID:
    logger.warning("Admin ID not loaded. The bot will not restrict access.")


# --- Keyboard Definitions ---

# Main Menu Reply Keyboard
main_menu_keyboard = ReplyKeyboardMarkup([
    [KeyboardButton('📊 HAProxy Status'), KeyboardButton('📜 List Tunnels')],
    [KeyboardButton('➕ Add Tunnel'), KeyboardButton('✏️ Edit Tunnel')],
    [KeyboardButton('❌ Delete Tunnel'), KeyboardButton('⚙️ Advanced Settings')]
], resize_keyboard=True, one_time_keyboard=False)

# Advanced Settings Inline Keyboard
advanced_settings_keyboard = InlineKeyboardMarkup([
    [InlineKeyboardButton("🚦 Set Health Check Port", callback_data='set_health_port')],
    [InlineKeyboardButton("🔄 Apply HAProxy Config", callback_data='apply_config')]
])

# --- Middleware ---
async def admin_only(update: Update, context: ContextTypes.DEFAULT_TYPE):
    # Check for admin ID in both message and callback query updates
    user_id = None
    if update.effective_user:
        user_id = str(update.effective_user.id)
    
    # Reload admin ID just in case it changed in the bash script
    global TELEGRAM_ADMIN_ID
    _, TELEGRAM_ADMIN_ID_RELOADED, _, _ = load_bash_config() # Reload admin ID from data file
    if TELEGRAM_ADMIN_ID_RELOADED:
        TELEGRAM_ADMIN_ID = TELEGRAM_ADMIN_ID_RELOADED
        logger.info(f"Admin ID reloaded: {TELEGRAM_ADMIN_ID}")
    
    if TELEGRAM_ADMIN_ID and user_id != TELEGRAM_ADMIN_ID:
        if update.message:
            await update.message.reply_text('You are not authorized to access this bot.')
        elif update.callback_query:
            await update.callback_query.answer("You are not authorized!", show_alert=True)
        logger.warning(f"Unauthorized access attempt by user ID: {user_id}")
        return False
    return True

# --- Utility Functions for running Bash Commands and Markdown Escaping ---
def escape_for_mdv2(text):
    # Telegram MarkdownV2 requires escaping of special characters.
    # Order matters: escape backslash first!
    text = str(text).replace('\\', '\\\\')
    # Escape all other special characters for MarkdownV2
    for char in ['_', '*', '[', ']', '(', ')', '~', '`', '>', '#', '+', '-', '=', '|', '{', '}', '.', '!']:
        text = text.replace(char, '\\' + char)
    return text

async def run_bash_command_and_reply(update: Update, context: ContextTypes.DEFAULT_TYPE, args: list, reply_to_msg_id=None) -> str:
    command_str = [BASH_SCRIPT_PATH] + args
    logger.info(f"Executing: {' '.join(command_str)}")

    try:
        process = subprocess.run(command_str, capture_output=True, text=True, check=False, encoding='utf-8')
        output = process.stdout.strip()
        error = process.stderr.strip()

        if process.returncode != 0:
            if "Success:" in output:
                response_text = f"*Command executed successfully!*\n`{escape_for_mdv2(output)}`"
            else:
                response_text = f"*Error executing command:*\n`{escape_for_mdv2(error or 'Unknown error')}`\n\n*Output:*\n`{escape_for_mdv2(output or 'No output')}`"
        else:
            response_text = f"*Command executed successfully!*\n`{escape_for_mdv2(output or 'No specific output')}`"

        if len(response_text) > 4096:
            truncated_response = response_text[:4000] + "\n\n... _(message truncated)_"
            await context.bot.send_message(
                chat_id=update.effective_chat.id,
                text=truncated_response,
                parse_mode='MarkdownV2',
                reply_to_message_id=reply_to_msg_id
            )
        else:
            await context.bot.send_message(
                chat_id=update.effective_chat.id,
                text=response_text,
                parse_mode='MarkdownV2',
                reply_to_message_id=reply_to_msg_id
            )
        return "Success"

    except FileNotFoundError:
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text=f"_Error: Bash script not found: {escape_for_mdv2(BASH_SCRIPT_PATH)}_",
            parse_mode='MarkdownV2',
            reply_to_message_id=reply_to_msg_id
        )
        logger.error(f"Bash script not found at {BASH_SCRIPT_PATH}")
        return "Error"

    except Exception as e:
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text=f"_Unexpected error: {escape_for_mdv2(str(e))}_",
            parse_mode='MarkdownV2',
            reply_to_message_id=reply_to_msg_id
        )
        logger.exception("An unexpected error occurred while running bash command.")
        return "Error"

# --- Command Handlers ---

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await admin_only(update, context): return
    await update.message.reply_text('Hello! ✋ I am the HAProxy management bot. Use the buttons or send /help to get started.', reply_markup=main_menu_keyboard)

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await admin_only(update, context): return
    help_text = """📚 Available Commands:
• /start \\- Start the bot and show the main menu
• /help \\- Show this guide
• 📊 \\*HAProxy Status\\* \\- Display HAProxy service status
• 📜 \\*List Tunnels\\* \\- View configured tunnels list
• ➕ \\*Add Tunnel\\* \\- Add a new tunnel
• ✏️ \\*Edit Tunnel\\* \\- Edit an existing tunnel
• ❌ \\*Delete Tunnel\\* \\- Delete a tunnel
• ⚙️ \\*Advanced Settings\\* \\- Access Health Check Port settings and manual config application
"""
    await update.message.reply_text(help_text, parse_mode='MarkdownV2', reply_markup=main_menu_keyboard)

async def show_haproxy_status_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await admin_only(update, context): return
    await update.message.reply_text('🔎 Checking HAProxy status...', reply_markup=main_menu_keyboard)
    
    try:
        # Command to check if HAProxy service is active
        cmd = ["sudo", "systemctl", "is-active", "haproxy"]
        logger.info(f"Executing: {' '.join(cmd)}")
        process = subprocess.run(cmd, capture_output=True, text=True, check=False, encoding='utf-8')
        
        status = process.stdout.strip()
        
        if status == "active":
            response_text = "*HAProxy is running\\. ✅*"
        else:
            response_text = "*HAProxy is stopped or has an error\\. ❌*\n_For more details, check logs with_ `sudo journalctl -u haproxy -f` _in terminal\\._"

        await update.message.reply_text(response_text, parse_mode='MarkdownV2')

    except Exception as e:
        await update.message.reply_text(f"_Unexpected error getting HAProxy status: {escape_for_mdv2(str(e))}_", parse_mode='MarkdownV2')
        logger.exception("An unexpected error occurred while getting HAProxy status.")


async def list_tunnels_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await admin_only(update, context): return
    await update.message.reply_text('⏳ Retrieving tunnel list...', reply_markup=main_menu_keyboard)
    
    # Reload config to get latest tunnels and health check port
    _, _, tunnels, health_port = load_bash_config()

    if not tunnels:
        response = "_No tunnels configured yet\\._"
    else:
        response = "*List of Tunnels:*\n"
        for tunnel in tunnels:
            # The 'id' field is now guaranteed to be present due to load_bash_config
            _id = escape_for_mdv2(str(tunnel.get('id', 'N/A')))
            _backend_ip = escape_for_mdv2(tunnel.get('backend_ip', 'N/A'))
            _ports = escape_for_mdv2(tunnel.get('ports', 'N/A'))
            _mode = escape_for_mdv2(tunnel.get('mode', 'N/A'))
            
            response += f"\n*ID:* {_id}\n"
            response += f"  *Backend IPs:* {_backend_ip}\n"
            response += f"  *Ports:* {_ports}\n"
            response += f"  *Mode:* {_mode}\n"
            response += escape_for_mdv2("------------------------------------\n") # Separator
    
    response += f"\n*Default Health Check Port:* {escape_for_mdv2(health_port or 'None')}"
    await update.message.reply_text(response, parse_mode='MarkdownV2', reply_markup=main_menu_keyboard)


# --- State-based Handlers for Add/Edit/Delete/Set Health Port ---
# Using context.user_data to store the state for multi-step commands

ADD_TUNNEL_STATE_IP = 10
ADD_TUNNEL_STATE_PORTS = 11
ADD_TUNNEL_STATE_MODE = 12

EDIT_TUNNEL_STATE_ID = 20
EDIT_TUNNEL_STATE_IP = 21
EDIT_TUNNEL_STATE_PORTS = 22
EDIT_TUNNEL_STATE_MODE = 23

DELETE_TUNNEL_STATE_ID = 30

SET_HEALTH_PORT_STATE = 40

async def add_tunnel_prompt(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not await admin_only(update, context): return
    await update.message.reply_text(
        '➕ Please enter Backend IP\\(s\\) \\(e\\.g\\.: 1\\.1\\.1\\.1,2\\.2\\.2\\.2 or \\[::1\\]\\):',
        parse_mode='MarkdownV2',
        reply_markup=main_menu_keyboard
    )
    context.user_data['command_state'] = ADD_TUNNEL_STATE_IP
    context.user_data['tunnel_data'] = {} # Initialize for new tunnel
    return ADD_TUNNEL_STATE_IP

async def edit_tunnel_prompt(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not await admin_only(update, context): return
    await update.message.reply_text('📜 Tunnels list for editing:')
    await list_tunnels_handler(update, context) # Show current tunnels
    await update.message.reply_text(
        '✏️ Please enter the ID of the tunnel you want to edit \\(e\\.g\\.: 0\\):',
        parse_mode='MarkdownV2',
        reply_markup=main_menu_keyboard
    )
    context.user_data['command_state'] = EDIT_TUNNEL_STATE_ID
    context.user_data['tunnel_data'] = {} # Initialize for edit
    return EDIT_TUNNEL_STATE_ID

async def delete_tunnel_prompt(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not await admin_only(update, context): return
    await update.message.reply_text('📜 Tunnels list for deletion:')
    await list_tunnels_handler(update, context) # Show current tunnels
    await update.message.reply_text(
        '❌ Please enter the ID of the tunnel you want to delete \\(e\\.g\\.: 0\\):',
        parse_mode='MarkdownV2',
        reply_markup=main_menu_keyboard
    )
    context.user_data['command_state'] = DELETE_TUNNEL_STATE_ID
    return DELETE_TUNNEL_STATE_ID

async def set_health_port_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not await admin_only(update, context): return
    query = update.callback_query
    await query.answer() # Acknowledge the callback query
    
    await context.bot.send_message(
        chat_id=query.message.chat_id,
        text='🚦 Please enter the new Health Check Port \\(e\\.g\\.: 80\\) or "none" to disable:',
        parse_mode='MarkdownV2',
        reply_markup=main_menu_keyboard
    )
    context.user_data['command_state'] = SET_HEALTH_PORT_STATE
    return SET_HEALTH_PORT_STATE

async def apply_config_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await admin_only(update, context): return
    query = update.callback_query
    await query.answer() # Acknowledge the callback query
    
    await context.bot.send_message(
        chat_id=query.message.chat_id,
        text='🔄 Applying HAProxy configuration and restarting service...',
        parse_mode='MarkdownV2',
        reply_markup=main_menu_keyboard
    )
    await run_bash_command_and_reply(query.message, context, ['--apply-config']) # Use query.message to reply

async def handle_text_input_for_state(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await admin_only(update, context): return
    current_state = context.user_data.get('command_state')
    user_input = update.message.text.strip()
    
    # --- ADD TUNNEL STATE ---
    if current_state == ADD_TUNNEL_STATE_IP:
        cleaned_input = user_input.replace(' ', '') # Remove spaces before validation
        # Regex for comma-separated IPv4 or IPv6 addresses.
        # This is simplified. For Python, using 'ipaddress' module would be ideal.
        if re.fullmatch(r'^(?:(?:[0-9]{1,3}\.){3}[0-9]{1,3}|\[?([0-9a-fA-F:]+)\]?)(?:,(?:(?:[0-9]{1,3}\.){3}[0-9]{1,3}|\[?([0-9a-fA-F:]+)\]?))*$', cleaned_input):
            context.user_data['tunnel_data']['backend_ip'] = cleaned_input
            await update.message.reply_text('➕ Please enter Ports \\(e\\.g\\.: 80,443\\):', parse_mode='MarkdownV2')
            context.user_data['command_state'] = ADD_TUNNEL_STATE_PORTS
        else:
            await update.message.reply_text('❌ Invalid IP\\(s\\) format\\. Please use format 1\\.1\\.1\\.1,2\\.2\\.2\\.2 or \\[::1\\]\\.', parse_mode='MarkdownV2')
            # Do not reset state, let them try again
    elif current_state == ADD_TUNNEL_STATE_PORTS:
        cleaned_input = user_input.replace(' ', '') # Remove spaces before validation
        # Regex to match comma-separated numbers, each between 1 and 65535
        if re.fullmatch(r'^(?:[1-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])(?:,(?:[1-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))*$', cleaned_input):
            context.user_data['tunnel_data']['ports'] = cleaned_input
            await update.message.reply_text('➕ Please enter Mode \\(tcp or http\\):', parse_mode='MarkdownV2')
            context.user_data['command_state'] = ADD_TUNNEL_STATE_MODE
        else:
            await update.message.reply_text('❌ Invalid Ports format\\. Please use format 80,443 and ports between 1 to 65535\\.', parse_mode='MarkdownV2')
    elif current_state == ADD_TUNNEL_STATE_MODE:
        mode = user_input.lower()
        if mode in ['tcp', 'http']:
            context.user_data['tunnel_data']['mode'] = mode
            backend_ips = context.user_data['tunnel_data']['backend_ip']
            ports = context.user_data['tunnel_data']['ports']
            
            # This is the call to the bash script to add the tunnel
            await run_bash_command_and_reply(update, context, ['--add-tunnel', backend_ips, ports, mode])
            
            context.user_data['command_state'] = None # Reset state
            context.user_data['tunnel_data'] = {}
        else:
            await update.message.reply_text('❌ Invalid Mode\\. Please enter tcp or http\\.')

    # --- EDIT TUNNEL STATE ---
    elif current_state == EDIT_TUNNEL_STATE_ID:
        if user_input.isdigit():
            context.user_data['tunnel_data']['id'] = user_input
            
            # Fetch current tunnel data for user
            try:
                # Reload config to get latest tunnels
                _, _, tunnels, _ = load_bash_config()
                
                # Find the tunnel by its assigned 'id'
                selected_tunnel = next((t for t in tunnels if str(t['id']) == user_input), None)
                if selected_tunnel:
                    context.user_data['tunnel_data']['backend_ip_current'] = selected_tunnel.get('backend_ip')
                    context.user_data['tunnel_data']['ports_current'] = selected_tunnel.get('ports')
                    context.user_data['tunnel_data']['mode_current'] = selected_tunnel.get('mode')

                    await update.message.reply_text(
                        f'✏️ \\*Editing Tunnel ID:* {escape_for_mdv2(user_input)}\n'
                        f'  \\*Current IPs:* {escape_for_mdv2(selected_tunnel.get("backend_ip", "N/A"))}\n'
                        f'  \\*Current Ports:* {escape_for_mdv2(selected_tunnel.get("ports", "N/A"))}\n'
                        f'  \\*Current Mode:* {escape_for_mdv2(selected_tunnel.get("mode", "N/A"))}\n'
                        '\nPlease enter new Backend IP\\(s\\) \\(e\\.g\\.: 1\\.1\\.1\\.1,2\\.2\\.2\\.2 or \\[::1\\]\\):',
                        parse_mode='MarkdownV2'
                    )
                    context.user_data['command_state'] = EDIT_TUNNEL_STATE_IP
                else:
                    await update.message.reply_text(f'❌ Tunnel with ID {escape_for_mdv2(user_input)} not found\\. Please enter a valid ID\\.', parse_mode='MarkdownV2')
                    # Do not reset state, let them try again
            except Exception as e:
                await update.message.reply_text(f'_Error retrieving tunnel information: {escape_for_mdv2(str(e))}_', parse_mode='MarkdownV2')
                context.user_data['command_state'] = None # Reset state on error
                context.user_data['tunnel_data'] = {}
        else:
            await update.message.reply_text('❌ Invalid ID\\. Please enter only a number\\.')

    elif current_state == EDIT_TUNNEL_STATE_IP:
        cleaned_input = user_input.replace(' ', '') # Remove spaces before validation
        if re.fullmatch(r'^(?:(?:[0-9]{1,3}\.){3}[0-9]{1,3}|\[?([0-9a-fA-F:]+)\]?)(?:,(?:(?:[0-9]{1,3}\.){3}[0-9]{1,3}|\[?([0-9a-fA-F:]+)\]?))*$', cleaned_input):
            context.user_data['tunnel_data']['backend_ip'] = cleaned_input
            await update.message.reply_text('✏️ Please enter new Ports \\(e\\.g\\.: 80,443\\):', parse_mode='MarkdownV2')
            context.user_data['command_state'] = EDIT_TUNNEL_STATE_PORTS
        else:
            await update.message.reply_text('❌ Invalid Ports format\\. Please use format 80,443 and ports between 1 to 65535\\.', parse_mode='MarkdownV2')
    elif current_state == EDIT_TUNNEL_STATE_PORTS:
        cleaned_input = user_input.replace(' ', '') # Remove spaces before validation
        if re.fullmatch(r'^(?:[1-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])(?:,(?:[1-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))*$', cleaned_input):
            context.user_data['tunnel_data']['ports'] = cleaned_input
            await update.message.reply_text('✏️ Please enter new Mode \\(tcp or http\\):', parse_mode='MarkdownV2')
            context.user_data['command_state'] = EDIT_TUNNEL_STATE_MODE
        else:
            await update.message.reply_text('❌ Invalid Ports format\\. Please use format 80,443 and ports between 1 to 65535\\.', parse_mode='MarkdownV2')
    elif current_state == EDIT_TUNNEL_STATE_MODE:
        mode = user_input.lower()
        if mode in ['tcp', 'http']:
            context.user_data['tunnel_data']['mode'] = mode
            _id = context.user_data['tunnel_data']['id']
            backend_ips = context.user_data['tunnel_data']['backend_ip']
            ports = context.user_data['tunnel_data']['ports']
            
            # Call bash script to edit the tunnel
            await run_bash_command_and_reply(update, context, ['--edit-tunnel', _id, backend_ips, ports, mode])
            
            context.user_data['command_state'] = None # Reset state
            context.user_data['tunnel_data'] = {}
        else:
            await update.message.reply_text('❌ Invalid Mode\\. Please enter tcp or http\\.')

    # --- DELETE TUNNEL STATE ---
    elif current_state == DELETE_TUNNEL_STATE_ID:
        if user_input.isdigit():
            context.user_data['tunnel_data']['id_to_delete'] = user_input
            keyboard = InlineKeyboardMarkup([
                [InlineKeyboardButton("✅ Yes", callback_data=f'delete_confirm_yes_{user_input}'),
                 InlineKeyboardButton("❌ No", callback_data='delete_confirm_no')]
            ])
            await update.message.reply_text(
                f'❓ Are you sure you want to delete tunnel with ID {escape_for_mdv2(user_input)}?',
                reply_markup=keyboard, parse_mode='MarkdownV2'
            )
        else:
            await update.message.reply_text('❌ Invalid ID\\. Please enter only a number\\.')
    
    # --- HEALTH CHECK PORT STATE ---
    elif current_state == SET_HEALTH_PORT_STATE:
        cleaned_input = user_input.replace(' ', '') # Remove spaces before validation
        if cleaned_input.lower() == 'none' or (cleaned_input.isdigit() and 1 <= int(cleaned_input) <= 65535):
            await run_bash_command_and_reply(update, context, ['--manage-health-check-port', cleaned_input.lower()])
            context.user_data['command_state'] = None # Reset state
        else:
            await update.message.reply_text('❌ Invalid port\\. Please enter a number or "none"\\.')

    # --- NO STATE ---
    else:
        # If no specific state, act as a general echo or unrecognized command
        await update.message.reply_text(f"_I didn't understand\\. Please use the buttons or /help command\\._", parse_mode='MarkdownV2', reply_markup=main_menu_keyboard)
        return


async def handle_delete_confirmation(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    await query.answer() # Acknowledge the callback query

    action = query.data
    if action.startswith('delete_confirm_yes_'):
        tunnel_id = action.replace('delete_confirm_yes_', '')
        await context.bot.send_message(
            chat_id=query.message.chat_id,
            text=f'🗑️ Deleting tunnel with ID {escape_for_mdv2(tunnel_id)}...',
            parse_mode='MarkdownV2',
            reply_markup=main_menu_keyboard
        )
        await run_bash_command_and_reply(query.message, context, ['--delete-tunnel', tunnel_id])
    elif action == 'delete_confirm_no':
        await context.bot.send_message(
            chat_id=query.message.chat_id,
            text='Tunnel deletion cancelled\\.',
            parse_mode='MarkdownV2',
            reply_markup=main_menu_keyboard
        )
    
    context.user_data['command_state'] = None # Reset state after confirmation
    context.user_data['tunnel_data'] = {}


async def advanced_settings_handler(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Shows the inline keyboard for advanced settings."""
    if not await admin_only(update, context): return
    await update.message.reply_text(
        '⚙️ *Advanced Settings:*',
        reply_markup=advanced_settings_keyboard,
        parse_mode='MarkdownV2'
    )


def main():
    # Reload token here again, in case it was updated while bot was running
    global TELEGRAM_BOT_TOKEN, TELEGRAM_ADMIN_ID
    TELEGRAM_BOT_TOKEN_RELOADED, TELEGRAM_ADMIN_ID_RELOADED, _, _ = load_bash_config()
    if TELEGRAM_BOT_TOKEN_RELOADED:
        TELEGRAM_BOT_TOKEN = TELEGRAM_BOT_TOKEN_RELOADED
    if TELEGRAM_ADMIN_ID_RELOADED:
        TELEGRAM_ADMIN_ID = TELEGRAM_ADMIN_ID_RELOADED
    
    if not TELEGRAM_BOT_TOKEN:
        logger.critical("Telegram bot token is not set. Bot cannot connect to Telegram API.")
        return # Exit if token is not set to prevent continuous restarts

    try:
        application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    except Exception as e:
        logger.critical(f"Failed to initialize Telegram Bot Application: {e}")
        logger.critical("Please ensure the Telegram Bot Token is correctly configured.")
        return # Exit if application builder fails

    # Command Handlers
    application.add_handler(CommandHandler("start", start_command))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(MessageHandler(filters.Regex('^📊 HAProxy Status$'), show_haproxy_status_handler))
    application.add_handler(MessageHandler(filters.Regex('^📜 List Tunnels$'), list_tunnels_handler))
    application.add_handler(MessageHandler(filters.Regex('^➕ Add Tunnel$'), add_tunnel_prompt))
    application.add_handler(MessageHandler(filters.Regex('^✏️ Edit Tunnel$'), edit_tunnel_prompt))
    application.add_handler(MessageHandler(filters.Regex('^❌ Delete Tunnel$'), delete_tunnel_prompt))
    application.add_handler(MessageHandler(filters.Regex('^⚙️ Advanced Settings$'), advanced_settings_handler))

    # Callback Query Handlers (for Inline Keyboards)
    application.add_handler(CallbackQueryHandler(set_health_port_callback, pattern='^set_health_port$'))
    application.add_handler(CallbackQueryHandler(apply_config_callback, pattern='^apply_config$'))
    application.add_handler(CallbackQueryHandler(handle_delete_confirmation, pattern='^delete_confirm_'))

    # Message Handler for multi-step inputs
    # IMPORTANT: This must be after other specific MessageHandlers (like regex ones for buttons)
    # because it acts as a fallback for any text message that's not a command or button.
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text_input_for_state))

    logger.info("Starting bot polling...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == '__main__':
    main()
EOF

    if [[ $? -ne 0 ]]; then
        error_msg "Failed to create Python bot script at ${CYAN}${PYTHON_BOT_SCRIPT_PATH}${NC}."
        error_msg "This could be due to permission issues or a malformed heredoc block."
        return 1
    fi
    success_msg "Python bot script generated at ${CYAN}${PYTHON_BOT_SCRIPT_PATH}${NC}."

    # Set appropriate permissions for the Python script and data file
    # Make sure the directory itself has execute for root if it's new
    # For /root/, it should already have 755 or 700.
    # We still ensure script and data file have specific permissions.
    sudo chmod +x install.sh
    sudo chmod 755 "$PYTHON_BOT_SCRIPT_PATH" # Executable by owner, readable by others (not strictly needed for root but good practice)
    sudo chmod 600 "$DATA_FILE" # Readable/writable only by owner (root)
    info_msg "Permissions adjusted for script and data file."

    # --- Generate Systemd Service File ---
    cat << EOF_SYSTEMD_SERVICE > "$SYSTEMD_SERVICE_FILE"
[Unit]
Description=HAProxy Tunnel Management Telegram Bot
After=network.target

[Service]
ExecStart=/usr/bin/python3 ${PYTHON_BOT_SCRIPT_PATH}
WorkingDirectory=${SCRIPT_DIR}
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=5
User=root
Environment=BASH_SCRIPT_PATH=${BASH_SCRIPT_FULL_PATH}

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD_SERVICE

    info_msg "Systemd service file generated at ${CYAN}${SYSTEMD_SERVICE_FILE}${NC}."
    info_msg "Reloading systemd daemon and enabling service..."
    sudo systemctl daemon-reload
    sudo systemctl enable haproxy-tunnel-bot || { error_msg "Failed to enable haproxy-tunnel-bot service. Check logs."; return 1; }
    sudo systemctl stop haproxy-tunnel-bot # Stop it first to ensure a clean start if already running
    sudo systemctl start haproxy-tunnel-bot || { error_msg "Failed to start haproxy-tunnel-bot service. Check 'sudo journalctl -u haproxy-tunnel-bot -f' for details."; return 1; }

    success_msg "Telegram Bot Systemd service created, enabled, and started."
    return 0
}


delete_systemd_service() {
    info_msg "Deleting Telegram Bot Systemd Service file and Python script..."

    if sudo systemctl is-active haproxy-tunnel-bot &>/dev/null; then
        info_msg "Stopping haproxy-tunnel-bot service..."
        sudo systemctl stop haproxy-tunnel-bot || warn_msg "Failed to stop haproxy-tunnel-bot service. Continuing with deletion."
    fi

    if sudo systemctl is-enabled haproxy-tunnel-bot &>/dev/null; then
        info_msg "Disabling haproxy-tunnel-bot service..."
        sudo systemctl disable haproxy-tunnel-bot || warn_msg "Failed to disable haproxy-tunnel-bot service. Continuing with deletion."
    fi

    if [[ -f "$SYSTEMD_SERVICE_FILE" ]]; then
        info_msg "Deleting Systemd service file: ${CYAN}${SYSTEMD_SERVICE_FILE}${NC}..."
        sudo rm -f "$SYSTEMD_SERVICE_FILE" || { error_msg "Failed to delete Systemd service file. Permissions issue?"; return 1; }
        success_msg "Systemd service file deleted."
    else
        warn_msg "Systemd service file not found at ${CYAN}${SYSTEMD_SERVICE_FILE}${NC}."
    fi

    if [[ -f "$PYTHON_BOT_SCRIPT_PATH" ]]; then
        info_msg "Deleting Python bot script: ${CYAN}${PYTHON_BOT_SCRIPT_PATH}${NC}..."
        rm -f "$PYTHON_BOT_SCRIPT_PATH" || { error_msg "Failed to delete Python bot script. Permissions issue?"; return 1; }
        success_msg "Python bot script deleted."
    else
        warn_msg "Python bot script not found at ${CYAN}${PYTHON_BOT_SCRIPT_PATH}${NC}."
    fi

    info_msg "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    success_msg "Telegram Bot Systemd service and script deleted."
    return 0
}

# --- Telegram Bot Service Control ---
start_telegram_bot_service() {
    info_msg "Starting Telegram Bot service..."
    sudo systemctl start haproxy-tunnel-bot || { error_msg "Failed to start Telegram Bot service. Check 'sudo journalctl -u haproxy-tunnel-bot -f' for details."; return 1; }
    success_msg "Telegram Bot service started."
}

restart_telegram_bot_service() {
    info_msg "Restarting Telegram Bot service..."
    sudo systemctl restart haproxy-tunnel-bot || { error_msg "Failed to restart Telegram Bot service. Check 'sudo journalctl -u haproxy-tunnel-bot -f' for details."; return 1; }
    success_msg "Telegram Bot service restarted."
}

stop_telegram_bot_service() {
    info_msg "Stopping Telegram Bot service..."
    sudo systemctl stop haproxy-tunnel-bot || { error_msg "Failed to stop Telegram Bot service. Check 'sudo journalctl -u haproxy-tunnel-bot -f' for details."; return 1; }
    success_msg "Telegram Bot service stopped."
}

show_telegram_bot_status() {
    info_msg "Showing Telegram Bot service status..."
    sudo systemctl status haproxy-tunnel-bot --no-pager
}

display_main_menu() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo -e "\n${BRIGHT_BLUE}--- HAProxy Tunnel Manager Menu ---${NC}"
        echo -e "${BLACK}1.${NC} 📊 ${BLACK}Show HAProxy Status${NC}"
        echo -e "${BLUE}2.${NC} 📜 ${BLUE}List Tunnels${NC}"
        echo -e "${GREEN}3.${NC} ➕ ${GREEN}Add Tunnel${NC}"
        echo -e "${CYAN}4.${NC} ✏️  ${CYAN}Edit Tunnel${NC}"
        echo -e "${RED}5.${NC} ❌ ${RED}Delete Tunnel${NC}"
        echo -e "${PINK}6.${NC} 🚦 ${PINK}Manage Health Check Port${NC}"
        echo -e "${ORANGE}7.${NC} 🔄 ${ORANGE}Apply HAProxy Config & Restart${NC}"
        echo -e "${MAGENTA}8.${NC} ⚙️  ${MAGENTA}Manage Telegram Bot Service${NC}"
        echo -e "${BRIGHT_RED}0.${NC} 🚪 ${BRIGHT_RED}Exit${NC}"
        echo -e "${BRIGHT_BLUE}----------------------------------${NC}"
        read -rp "${BRIGHT_YELLOW}Please choose an option: ${NC}" choice
    fi
}

show_telegram_bot_menu() {
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo -e "\n${LIGHT_CYAN}--- Telegram Bot Management ---${NC}"
        echo -e "${GREEN}1.${NC} ⚙️  ${GREEN}Configure Telegram Bot Token/Admin ID${NC}"
        echo -e "${BLUE}2.${NC} ▶️ ${BLUE}Start Telegram Bot${NC}"
        echo -e "${BLUE}3.${NC} 🔄 ${BLUE}Restart Telegram Bot${NC}"
        echo -e "${BLUE}4.${NC} ⏸️  ${BLUE}Stop Telegram Bot${NC}"
        echo -e "${BLUE}5.${NC} ✨ ${BLUE}Regenerate Bot Systemd Service File (and install dependencies)${NC}"
        echo -e "${ORANGE}6.${NC} 📊 ${ORANGE}Show Telegram Bot Status${NC}"
        echo -e "${BRIGHT_RED}7.${NC} 🗑️  ${BRIGHT_RED}Delete Telegram Bot Service & Files${NC}"
        echo -e "${BRIGHT_RED}0.${NC} ↩️  ${BRIGHT_RED}Back to Main Menu${NC}"
        echo -e "${LIGHT_CYAN}-------------------------------${NC}"
        read -rp "${BRIGHT_YELLOW}Please choose an option: ${NC}" telegram_choice
    fi
}

# --- Main Script Logic ---
INTERACTIVE_MODE="true"

if [[ "$1" == "--list-tunnels" ]]; then
    INTERACTIVE_MODE="false"
    load_data
    list_tunnels
    exit 0
elif [[ "$1" == "--add-tunnel" ]]; then
    INTERACTIVE_MODE="false"
    load_data
    shift
    add_tunnel "$@"
    exit $?
elif [[ "$1" == "--edit-tunnel" ]]; then
    INTERACTIVE_MODE="false"
    load_data
    shift
    edit_tunnel "$@"
    exit $?
elif [[ "$1" == "--delete-tunnel" ]]; then
    INTERACTIVE_MODE="false"
    load_data
    shift
    delete_tunnel "$@"
    exit $?
elif [[ "$1" == "--manage-health-check-port" ]]; then
    INTERACTIVE_MODE="false"
    load_data
    shift
    manage_health_check_port "$@"
    exit $?
elif [[ "$1" == "--apply-config" ]]; then
    INTERACTIVE_MODE="false"
    load_data
    apply_haproxy_config
    exit $?
elif [[ "$1" == "--show-status" ]]; then
    INTERACTIVE_MODE="false"
    show_haproxy_status
    exit $?
elif [[ "$1" == "--create-systemd-service" ]]; then
    INTERACTIVE_MODE="false"
    create_bot_systemd_service
    exit $?
elif [[ "$1" == "--delete-systemd-service" ]]; then
    INTERACTIVE_MODE="false"
    delete_systemd_service
    exit $?
elif [[ "$1" == "--get-data" ]]; then
    INTERACTIVE_MODE="false"
    load_data
    # 'local' keywords are removed here as this block is not inside a function
    tunnels_json_content="" # این متغیر فقط محتوای داخل آرایه را نگه می‌دارد
    first_tunnel=true
    for t_str in "${TUNNELS[@]}"; do
        if [[ "$first_tunnel" = false ]]; then
            tunnels_json_content+=","
        fi
        tunnels_json_content+="$t_str"
        first_tunnel=false
    done
    final_tunnels_json="[${tunnels_json_content}]" # اینجا آرایه را با کروشه می‌سازیم

    escaped_health_check_port=$(printf %s "$HEALTH_CHECK_PORT" | sed 's/"/\\"/g')
    escaped_telegram_bot_token=$(printf %s "$TELEGRAM_BOT_TOKEN" | sed 's/"/\\"/g')
    escaped_telegram_admin_id=$(printf %s "$TELEGRAM_ADMIN_ID" | sed 's/"/\\"/g')

    # این خط خروجی نهایی JSON را تولید می‌کند
    echo "{\"HEALTH_CHECK_PORT\":\"$escaped_health_check_port\", \"TELEGRAM_BOT_TOKEN\":\"$escaped_telegram_bot_token\", \"TELEGRAM_ADMIN_ID\":\"$escaped_telegram_admin_id\", \"tunnels\":$final_tunnels_json}"
    exit 0
fi

check_dependencies || exit 1
load_data

configure_journald_for_logs

while true; do
    display_main_menu
    case "$choice" in
        1) show_haproxy_status ;;
        2) list_tunnels ;;
        3) add_tunnel ;;
        4) edit_tunnel ;;
        5) delete_tunnel ;;
        6) manage_health_check_port ;;
        7) apply_haproxy_config ;;
        8)
            while true; do
                show_telegram_bot_menu
                case "$telegram_choice" in
                    1) configure_telegram_bot ;;
                    2) start_telegram_bot_service ;;
                    3) restart_telegram_bot_service ;;
                    4) stop_telegram_bot_service ;;
                    5) create_bot_systemd_service ;;
                    6) show_telegram_bot_status ;;
                    7) delete_systemd_service ;;
                    0) break ;; # Back to Main Menu
                    *) error_msg "Invalid choice. Please try again." ;;
                esac
                read -rp "Press Enter to continue..."
            done
            ;;
        0) info_msg "Exiting script."; exit 0 ;;
        *) error_msg "Invalid choice. Please try again." ;;
    esac
    # Only prompt "Press Enter" if not returning from a sub-menu loop
    if [[ "$choice" != "8" ]]; then
        read -rp "Press Enter to continue..."
    fi
done
