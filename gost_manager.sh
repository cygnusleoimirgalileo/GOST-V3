#!/bin/bash

# Check if the script is running interactively
if [[ -t 0 ]]; then
    # Interactive shell, proceed
    :
else
    echo -e "${RED}Error: This script must be run interactively. Please download it and run with 'sudo bash gost_manager.sh'${NC}"
    echo -e "${BLUE}Download command: wget -O gost_manager.sh https://raw.githubusercontent.com/cygnusleoimirgalileo/GOST-V3/main/gost_manager.sh${NC}"
    exit 1
fi

# --- Colors for better visual presentation ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Check for root privileges ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run this script with root privileges (e.g., sudo bash gost_manager.sh)${NC}"
    exit 1
fi

# --- Global variables ---
config_file="/usr/local/bin/gost.yml"
mode_file="/usr/local/bin/.gost_mode"
gost_file="/usr/local/bin/gost"

# --- Function Definitions ---

check_gost_file() {
    if [ ! -f "$gost_file" ]; then
        echo -e "${YELLOW}GOST file not found in /usr/local/bin. Downloading GOST core...${NC}"
        download_gost
    fi
}

download_gost() {
    echo -e "${BLUE}Downloading and installing GOST v3...${NC}"
    # Add your download and extraction logic for GOST here
    # Replace the URL and extraction steps with actual ones for your GOST version
    wget -O /tmp/gost_v3.tar.gz "https://example.com/gost_v3.tar.gz" || { echo -e "${RED}Error: Download failed.${NC}"; exit 1; }
    tar -xvzf /tmp/gost_v3.tar.gz -C /usr/local/bin/ || { echo -e "${RED}Error: Failed to extract GOST archive.${NC}"; exit 1; }
    chmod +x /usr/local/bin/gost
    rm -f /tmp/gost_v3.tar.gz
    echo -e "${GREEN}GOST v3 installed successfully!${NC}"
}

# Removed the check for server mode change (option 8)

# Function for updating the script and GOST core file
update_script_and_gost() {
    echo -e "${BLUE}Updating the GOST manager script...${NC}"
    wget -O "$0" https://raw.githubusercontent.com/cygnusleoimirgalileo/GOST-V3/main/gost_manager.sh || { echo -e "${RED}Error: Script update failed.${NC}"; exit 1; }
    chmod +x "$0"
    echo -e "${GREEN}GOST manager script updated successfully!${NC}"
    download_gost
}

# Function for complete uninstallation
uninstall() {
    echo -e "${YELLOW}Uninstalling the script and all related files...${NC}"
    rm -f "$gost_file" "$config_file" "$mode_file" "/etc/systemd/system/gost.service"
    systemctl daemon-reload
    echo -e "${GREEN}Uninstallation complete.${NC}"
    exit 0
}

# --- Function Definitions Continued ---
check_first_run() {
    if [ ! -f "$mode_file" ]; then
        echo -e "${YELLOW}Is this server Foreign or Domestic?${NC}"
        echo -e "${CYAN}Foreign server${NC} - Receives connections and forwards to local services"
        echo -e "${CYAN}Domestic server${NC} - Connects to a foreign server and forwards traffic"
        echo
        read -p "Enter 'f' for Foreign, 'd' for Domestic: " mode_choice
        case "$mode_choice" in
            f|F)
                SERVER_MODE="foreign"
                ;;
            d|D)
                SERVER_MODE="domestic"
                ;;
            *)
                echo -e "${YELLOW}Invalid input. Defaulting to Foreign mode.${NC}"
                SERVER_MODE="foreign"
                ;;
        esac
        echo "$SERVER_MODE" > "$mode_file"
        return 0 # First run
    else
        SERVER_MODE=$(cat "$mode_file" 2>/dev/null || echo "foreign")
        if [ -z "$SERVER_MODE" ]; then
            echo -e "${YELLOW}Mode file is empty, defaulting to Foreign${NC}"
            SERVER_MODE="foreign"
            echo "$SERVER_MODE" > "$mode_file"
        fi
        return 1 # Not first run
    fi
}

display_services() {
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}No configuration file found ($config_file).${NC}"
        echo -e "${BLUE}Creating an empty configuration file.${NC}"
        echo "services: []" > "$config_file"
        service_count=0
    else
        service_count=$(/usr/bin/yq eval '.services | length' "$config_file")
        if [ "$service_count" -eq 0 ]; then
            echo -e "${YELLOW}No active services found in $config_file.${NC}"
        else
            echo -e "${GREEN}Number of active services: $service_count${NC}"
            echo -e "${CYAN}Current services:${NC}"
            readarray -t service_names < <(/usr/bin/yq eval '.services[].name' "$config_file")
            for i in "${!service_names[@]}"; do
                echo -e "${CYAN}$(($i+1))${NC}. ${service_names[$i]}"
            done
            echo
            echo -e "${YELLOW}Would you like to view the configuration of a specific service? (Y/n)${NC}"
            read -p "Choice: " show_choice
            if [[ ! "$show_choice" =~ ^[Nn] ]]; then
                echo -e "${YELLOW}Enter the number of the service to view:${NC}"
                read -p "Service number: " service_num
                if [[ "$service_num" =~ ^[0-9]+$ ]] && [ "$service_num" -ge 1 ] && [ "$service_num" -le "${#service_names[@]}" ]; then
                    service_name="${service_names[$(($service_num-1))]}"
                    echo -e "\n${PURPLE}=== Configuration for service: $service_name ===${NC}"
                    /usr/bin/yq eval ".services[] | select(.name == \"$service_name\")" "$config_file"
                else
                    echo -e "${RED}Invalid service number.${NC}"
                fi
            fi
        fi
    fi
}

add_service() {
    if [ ! -f "$config_file" ]; then
        echo "services: []" > "$config_file"
    fi
    if [ "$SERVER_MODE" == "foreign" ]; then
        echo -e "${CYAN}Adding a new service for Foreign mode...${NC}"
        read -p "Enter service name: " name
        read -p "Enter listening port (e.g., 9081): " listen_port
        read -p "Enter redirect port (for forwarding to localhost) (e.g., 443): " redirect_port
        tmp_file=$(mktemp)
        cat > "$tmp_file" << EOFX
services:
  - name: "$name"
    addr: ":$listen_port"
    handler:
      type: tcp
    listener:
      type: tcp
    forwarder:
      nodes:
        - addr: "localhost:$redirect_port"
          connector:
            type: forward
            dialer:
              type: tcp
EOFX
        if [ -s "$config_file" ]; then
            /usr/bin/yq eval-all 'select(fileIndex == 0).services = select(fileIndex == 0).services + select(fileIndex == 1).services | select(fileIndex == 0)' "$config_file" "$tmp_file" > "${config_file}.new"
            mv "${config_file}.new" "$config_file"
        else
            cp "$tmp_file" "$config_file"
        fi
        rm "$tmp_file"
    else
        echo -e "${CYAN}Adding a new service for Domestic mode...${NC}"
        read -p "Enter service name: " name
        read -p "Enter listening port (e.g., 8585): " listen_port
        read -p "Enter foreign server IPv6 address (without brackets): " foreign_ipv6
        read -p "Enter destination port (for forwarding) (e.g., 8585): " dest_port
        dest_addr="[${foreign_ipv6}]:${dest_port}"
        tmp_file=$(mktemp)
        cat > "$tmp_file" << EOFX
services:
  - name: "$name"
    addr: ":$listen_port"
    handler:
      type: tcp
    forwarder:
      nodes:
        - addr: "$dest_addr"
          connector:
            type: forward
            dialer:
              type: tcp
EOFX
        if [ -s "$config_file" ]; then
            /usr/bin/yq eval-all 'select(fileIndex == 0).services = select(fileIndex == 0).services + select(fileIndex == 1).services | select(fileIndex == 0)' "$config_file" "$tmp_file" > "${config_file}.new"
            mv "${config_file}.new" "$config_file"
        else
            cp "$tmp_file" "$config_file"
        fi
        rm "$tmp_file"
    fi
    echo -e "${GREEN}Service '$name' added successfully.${NC}"
}

remove_service() {
    display_services
    if [ -f "$config_file" ] && [ "$(/usr/bin/yq eval '.services | length' "$config_file")" -gt 0 ]; then
        echo -e "${YELLOW}Enter the number of the service to remove:${NC}"
        read -p "Service number: " service_num
        readarray -t service_names < <(/usr/bin/yq eval '.services[].name' "$config_file")
        if [[ "$service_num" =~ ^[0-9]+$ ]] && [ "$service_num" -ge 1 ] && [ "$service_num" -le "${#service_names[@]}" ]; then
            name="${service_names[$(($service_num-1))]}"
            /usr/bin/yq eval -i 'del(.services[] | select(.name == "'"$name"'"))' "$config_file"
            echo -e "${GREEN}Service '$name' removed successfully.${NC}"
        else
            echo -e "${RED}Invalid service number.${NC}"
        fi
    else
        echo -e "${YELLOW}No services available to remove.${NC}"
    fi
}

edit_service() {
    display_services
    if [ -f "$config_file" ] && [ "$(/usr/bin/yq eval '.services | length' "$config_file")" -gt 0 ]; then
        echo -e "${YELLOW}Enter the number of the service to edit:${NC}"
        read -p "Service number: " service_num
        readarray -t service_names < <(/usr/bin/yq eval '.services[].name' "$config_file")
        if [[ "$service_num" =~ ^[0-9]+$ ]] && [ "$service_num" -ge 1 ] && [ "$service_num" -le "${#service_names[@]}" ]; then
            name="${service_names[$(($service_num-1))]}"
            if /usr/bin/yq eval ".services[] | select(.name == \"${name}\")" "$config_file" > /dev/null 2>&1; then
                if [ "$SERVER_MODE" == "foreign" ]; then
                    read -p "Enter new listening port (e.g., 9081): " listen_port
                    read -p "Enter new redirect port (for forwarding to localhost) (e.g., 443): " redirect_port
                    /usr/bin/yq eval -i '(.services[] | select(.name == "'"$name"'")).addr = ":'"$listen_port"'"' "$config_file"
                    /usr/bin/yq eval -i '(.services[] | select(.name == "'"$name"'")).forwarder.nodes[0].addr = "localhost:'"$redirect_port"'"' "$config_file"
                else
                    read -p "Enter new listening port (e.g., 8585): " listen_port
                    read -p "Enter new foreign server IPv6 address (without brackets): " foreign_ipv6
                    read -p "Enter new destination port (for forwarding) (e.g., 8585): " dest_port
                    dest_addr="[${foreign_ipv6}]:${dest_port}"
                    /usr/bin/yq eval -i '(.services[] | select(.name == "'"$name"'")).addr = ":'"$listen_port"'"' "$config_file"
                    /usr/bin/yq eval -i '(.services[] | select(.name == "'"$name"'")).forwarder.nodes[0].addr = "'"$dest_addr"'"' "$config_file"
                fi
                echo -e "${GREEN}Service '$name' updated successfully.${NC}"
            else
                echo -e "${RED}Error: Service '$name' not found.${NC}"
            fi
        else
            echo -e "${RED}Invalid service number.${NC}"
        fi
    else
        echo -e "${YELLOW}No services available to edit.${NC}"
    fi
}

create_service_file() {
    echo -e "${BLUE}Creating GOST service file...${NC}"
    cat <<EOFX > /etc/systemd/system/gost.service
[Unit]
Description=GO Simple Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -C /usr/local/bin/gost.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOFX
    systemctl daemon-reload
}

start_service() {
    if [ ! -f "/etc/systemd/system/gost.service" ]; then
        create_service_file
    fi
    echo -e "${BLUE}Starting GOST service...${NC}"
    systemctl enable gost.service
    systemctl start gost.service
    if systemctl is-active gost.service | grep -q "active"; then
        echo -e "${GREEN}GOST service is running successfully!${NC}"
    else
        echo -e "${RED}Warning: GOST service failed to start. Check 'systemctl status gost.service' for details.${NC}"
    fi
}

restart_service() {
    if [ ! -f "/etc/systemd/system/gost.service" ]; then
        create_service_file
    fi
    echo -e "${BLUE}Restarting GOST service...${NC}"
    systemctl restart gost.service
    if systemctl is-active gost.service | grep -q "active"; then
        echo -e "${GREEN}GOST service restarted successfully!${NC}"
    else
        echo -e "${RED}Warning: GOST service failed to restart. Check 'systemctl status gost.service' for details.${NC}"
    fi
}

stop_service() {
    echo -e "${BLUE}Stopping GOST service...${NC}"
    systemctl stop gost.service
    if ! systemctl is-active gost.service | grep -q "active"; then
        echo -e "${GREEN}GOST service stopped successfully.${NC}"
    else
        echo -e "${RED}Warning: Failed to stop GOST service.${NC}"
    fi
}

show_header() {
    clear
    echo -e "${PURPLE}================================================${NC}"
    echo -e "${PURPLE}              GOST v3 Manager                   ${NC}"
    echo -e "${PURPLE}================================================${NC}"
    echo
    echo -e "${CYAN}Server Mode: ${SERVER_MODE^}${NC}"
    echo -e "${YELLOW}Date: $(date)${NC}"
    echo
    if systemctl is-active gost.service >/dev/null 2>&1; then
        echo -e "${GREEN}GOST Service: Running${NC}"
    else
        echo -e "${RED}GOST Service: Stopped${NC}"
    fi
    echo
}

# --- First Run Setup ---
check_first_run
is_first_run=$?

if [ "$is_first_run" -eq 0 ]; then
    # Install dependencies
    echo -e "${BLUE}Installing dependencies (wget only)...${NC}"
    apt update && apt install -y wget || {
        echo -e "${RED}Error: Failed to install dependencies. Check your network or permissions.${NC}"
        exit 1
    }

    # Ensure Go-based yq is installed
    if ! [ -x "/usr/bin/yq" ] || ! /usr/bin/yq --version | grep -q "mikefarah"; then
        echo -e "${BLUE}Installing Go-based yq...${NC}"
        VERSION=v4.40.5
        BINARY=yq_linux_amd64
        wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/bin/yq
        chmod +x /usr/bin/yq
    fi

    # Detect architecture and choose correct asset
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            asset_pattern="linux_amd64.tar.gz"
            ;;
        aarch64)
            asset_pattern="linux_arm64.tar.gz"
            ;;
        armv7l)
            asset_pattern="linux_arm.tar.gz"
            ;;
        *)
            asset_pattern="linux_amd64.tar.gz"
            ;;
    esac

    # Install GOST v3 if not already installed
    if ! command -v /usr/local/bin/gost &>/dev/null || ! /usr/local/bin/gost -V | grep -q "3\."; then
        echo -e "${BLUE}Downloading and installing GOST v3...${NC}"
        download_url=$(curl -s https://api.github.com/repos/go-gost/gost/releases | \
            grep -oP '"browser_download_url": "\K(.*?'"$asset_pattern"')(?=")' | \
            grep -E 'v3\.' | head -n 1)
        if [ -z "$download_url" ]; then
            echo -e "${RED}Error: Could not find a GOST v3 pre-release for $asset_pattern.${NC}"
            exit 1
        fi
        wget -O /tmp/gost_v3.tar.gz "$download_url" || { echo -e "${RED}Error: Download failed.${NC}"; exit 1; }
        tar -xvzf /tmp/gost_v3.tar.gz -C /usr/local/bin/ || { echo -e "${RED}Error: Failed to extract GOST archive.${NC}"; exit 1; }
        chmod +x /usr/local/bin/gost
        rm -f /tmp/gost_v3.tar.gz
        echo -e "${GREEN}GOST v3 installed successfully!${NC}"
    else
        echo -e "${GREEN}GOST v3 is already installed.${NC}"
    fi

    # Initial Configuration
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}No configuration file found.${NC}"
        read -p "Would you like to configure initial services now? (Y/n): " init_choice
        if [[ "$init_choice" =~ ^[Nn] ]]; then
            echo -e "${BLUE}Creating an empty configuration file.${NC}"
            echo "services: []" > "$config_file"
        else
            read -p "How many services do you want to configure initially? " count
            if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -lt 1 ]; then
                echo -e "${YELLOW}Invalid number, creating an empty configuration.${NC}"
                echo "services: []" > "$config_file"
            else
                echo "services: []" > "$config_file"
                for ((i=1; i<=count; i++)); do
                    echo -e "${CYAN}Configuring service #$i${NC}"
                    add_service
                done
            fi
        fi
    fi

    # Create and start service
    create_service_file
    start_service

    # Inside the 'if [ "$is_first_run" -eq 0 ]' block
shortcut_path="/usr/local/bin/gost-manager"
script_path="$(realpath "$0")"
if [ ! -f "$shortcut_path" ]; then
    echo "Creating shortcut 'gost-manager' to run this script..."
    sudo ln -sf "$script_path" "$shortcut_path"
    sudo chmod +x "$shortcut_path"
    echo "Shortcut 'gost-manager' created! Run with 'sudo gost-manager' in the future."
fi
fi

# --- Management Menu ---
while true; do
    show_header
    echo -e "${YELLOW}=== Management Menu ===${NC}"
    echo -e "${CYAN}1.${NC} Display services"
    echo -e "${CYAN}2.${NC} Add a new service"
    echo -e "${CYAN}3.${NC} Remove a service"
    echo -e "${CYAN}4.${NC} Edit a service"
    echo -e "${CYAN}5.${NC} Start GOST service"
    echo -e "${CYAN}6.${NC} Restart GOST service"
    echo -e "${CYAN}7.${NC} Stop GOST service"
    echo -e "${CYAN}8.${NC} Update script and GOST core"
    echo -e "${CYAN}9.${NC} Complete Uninstall"
    echo -e "${CYAN}10.${NC} Exit"
    echo
    read -p "Choose an option: " choice
    case "$choice" in
        1) display_services ;;
        2) add_service ;;
        3) remove_service ;;
        4) edit_service ;;
        5) start_service ;;
        6) restart_service ;;
        7) stop_service ;;
        8) update_script_and_gost ;;
        9) uninstall ;;
        10) echo -e "${GREEN}Exiting...${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid option. Please try again.${NC}" ;;
    esac
    echo
    read -p "Press Enter to continue..."
done
