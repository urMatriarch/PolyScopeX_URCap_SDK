#!/bin/bash

ROBOT_USER="root"
SSH_CONFIG_PATH="/etc/ssh/sshd_config"
ROBOT_ANGULAR_PORT=4200 #This is the port on the robot side. It should match what is in angular.json and in manifest
DEV_ANGULAR_PORT=4200   #This is the port on the devcontainer side. It should match what is in devcontainer.json and what is used by ng serve
ROBOT_CHROME_DEBUG_PORT=9222    #This is the port on the robot side. It should match what used by Chrome on the robot
DEV_CHROME_DEBUG_PORT=9222      #This is the port on the devcontainer side. It should match what used is in devcontainer.json
LOCAL_CHROME_DEBUG_HOST="127.0.0.1:${DEV_CHROME_DEBUG_PORT}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color


prepare_connection() {
    # Ensure SSH key exists
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        echo "Generating SSH key..."
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ""
    fi

    # Check if key is already installed
    TARGET="$ROBOT_USER@$ROBOT_HOST"
    if ! ssh -o BatchMode=yes "$TARGET" 'echo Connected' 2>/dev/null; then
        echo "SSH key not installed — copying now..."
        ssh-copy-id -i "$HOME/.ssh/id_ed25519.pub" "$TARGET"
    fi

}


ssh_connect_enable_forwarding() {
    REMOTE_SCRIPT=$(cat <<'EOF'
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"
SSH_CONFIG_PATH="/etc/ssh/sshd_config"

echo -e "${YELLOW}Go to robot and confirm remote debug enabling${NC}"
export DISPLAY=:0
xmessage -buttons "Cancel:1,Accept:0" \
            -font "-*-helvetica-bold-r-*-*-16-*-*-*-*-*-*-*" \
            -center -geometry 720x480+0+0 \
            "You are about to transfer control from this Teach Pendant (TP) to an external 
control station.

By proceeding, you acknowledge and accept that control will be relinquished 
from this TP.

Please note:
- The external control station SHALL be equipped with an Emergency Stop (E-stop).
- You may reclaim control at any time directly from this TP.

Do you wish to proceed?"
response=$?
case $response in
    0) echo -e "Remote debug confirmed"; ;;
    1) echo -e "${RED}Remote debug refused${NC}"; exit 1;;
    *) echo -e "${RED}Dialog closed${NC}"; exit 2;;
esac      
echo "Editing SSH config..."
sed -i "/^[#]*AllowTcpForwarding/c\\AllowTcpForwarding yes" "$SSH_CONFIG_PATH"
echo "Restarting SSH service..."
systemctl restart ssh
sleep 2
echo "SSH configuration updated and service restarted."
EOF
    )

    ssh $SSH_OPTIONS "$ROBOT_USER@$ROBOT_HOST" bash -s <<< "$REMOTE_SCRIPT"
    SSH_EXIT=$?
    if [ $SSH_EXIT -ne 0 ]; then
        if [ $SSH_EXIT -gt 2 ]; then
            echo -e "${RED}SSH failed with exit code $SSH_EXIT${NC}"
        fi
        exit 1
    fi
}

print_guidance() { 
    # Fetch the JSON from Chrome's remote debugging endpoint
    json=$(curl -s "http://${LOCAL_CHROME_DEBUG_HOST}/json")

    # For Chrome 144 and above multiple instances is returned. Find the right one
    block=$(echo "$json" | tr -d '\n' | grep -oP '\{.*?"title":\s*"Universal Robots".*?\}')
    if [ -z "$block" ]; then
        block=$(echo "$json" | grep -oP '(?s)\{.*?\}' | head -n1)
    fi

    # Extract the devtoolsFrontendUrl from the first entry
    url_path=$(echo "$block" | grep -oP '"devtoolsFrontendUrl":\s*"\K[^"]+')

    # Compose the full URL
    if [[ "$url_path" =~ ^(https?://|devtools://) ]]; then
        full_url="$url_path"
    else
        full_url="http://${LOCAL_CHROME_DEBUG_HOST}${url_path}"
    fi
    # Print a short, clickable link
    echo -e "${GREEN}\033]8;;$full_url\033\\Open Chrome remote DevTools\033]8;;\033\\ ${NC} or paste ${MAGENTA}chrome://inspect ${NC}in your Chrome to inspect target"
}

end_debug() {
    REMOTE_SCRIPT='
SSH_CONFIG_PATH="/etc/ssh/sshd_config"
pkill -9 -f "sshd: root@"
sed -i "/^[#]*AllowTcpForwarding/c\\AllowTcpForwarding no" "$SSH_CONFIG_PATH"
systemctl restart ssh
pkill xmessage'

    ssh $SSH_OPTIONS "$ROBOT_USER@$ROBOT_HOST" env TERM=xterm bash -s <<< "$REMOTE_SCRIPT" 2>/dev/null
}

make_port_forwarding() {
    REMOTE_SCRIPT='
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"
SSH_CONFIG_PATH="/etc/ssh/sshd_config"

export DISPLAY=:0

# Function to show xmessage and store its PID
show_xmessage() {
    xmessage -buttons "Stop session:1" \
             -font "-*-helvetica-bold-r-*-*-24-*-*-*-*-*-*-*" \
             -center -geometry 1260x784+0+0 \
             "This Teach Pendant (TP) is currently not in control.
An external control station is actively managing the system.

To regain control, please stop the session." > /dev/null 2>&1 &
    disown
    echo $! > /tmp/xmessage_pid
}

# Function to monitor window stacking
monitor_window() {
    while true; do
        # Poll the window stacking every 0.1 seconds
        sleep 0.1
        # Capture xwininfo output once per loop for performance
        xwininfo_output=$(xwininfo -root -tree)
        # Extract the window ID of the first xmessage instance
        xmessage_id=$(echo "$xwininfo_output" | grep -m1 "\"xmessage\"" | awk "{print \$1}")
        # Extract all child window IDs
        windows=$(echo "$xwininfo_output" | awk "/children:/{flag=1; next} flag && /0x[0-9a-fA-F]+/{print \$1}")
        # Get the topmost window ID
        top_window=$(echo "$windows" | head -1)
        # Read the current xmessage PID from file
        current_pid=$(cat /tmp/xmessage_pid 2>/dev/null)

        # Check if xmessage is still running
        if ! kill -0 "$current_pid" 2>/dev/null; then
            # xmessage was closed manually — exit monitor
            break
        fi

        # If xmessage is no longer the top window, re-display it 
        if [ "$top_window" != "$xmessage_id" ]; then
            # Kill the old xmessage process if it exists
            kill -9 "$current_pid" 2>/dev/null
            # Launch a new blocking xmessage window
            (show_xmessage) > /dev/null 2>&1
            echo "Browser refreshed..."
            # Allow time for the new message to appear
            sleep 1
        fi
    done
}

# Start xmessage and monitor
show_xmessage > /dev/null 2>&1
sleep 1
monitor_window &

# Wait until user closes xmessage manually
while true; do
    current_pid=$(cat /tmp/xmessage_pid 2>/dev/null)
    if ! kill -0 "$current_pid" 2>/dev/null; then
        wait "$current_pid"
        exit_code=$?
        if [ "$exit_code" -eq 0 ]; then
            break
        fi
    fi
    sleep 1
done

echo -e "${RED}Remote debug stopped${NC}"
sed -i "/^[#]*AllowTcpForwarding/c\\AllowTcpForwarding no" "$SSH_CONFIG_PATH"
pkill -9 -f "sshd: root@"
systemctl restart ssh
'
    ssh $SSH_OPTIONS -NT -R "$ROBOT_ANGULAR_PORT:localhost:$DEV_ANGULAR_PORT" "$ROBOT_USER@$ROBOT_HOST" &
    ssh $SSH_OPTIONS -L "$ROBOT_CHROME_DEBUG_PORT:localhost:$DEV_CHROME_DEBUG_PORT" "$ROBOT_USER@$ROBOT_HOST" bash -s <<< "$REMOTE_SCRIPT" &
    SSH_PID=$!

    # Wait for tunnel to be ready
    echo "Waiting for SSH tunnel to be ready..."
    for i in {1..10}; do
        if curl -s "http://${LOCAL_CHROME_DEBUG_HOST}/json" >/dev/null; then
            echo "Tunnel is up!"
            print_guidance       
            echo "Press Enter to close the SSH tunnel..."
            read
            end_debug
            return
        fi
        sleep 1
    done

    echo -e "${RED}SSH tunnel failed to start within timeout.${NC}"
    kill $SSH_PID 2>/dev/null
    exit 1
}


# Get target IP
if [ -n "$1" ]; then
    ROBOT_HOST="$1"
else
    prompt="$(echo -e "${YELLOW} Enter target IP: e.g. 192.168.1.1${NC} ")"
    read -p "$prompt" ROBOT_HOST
fi

SSH_OPTIONS="-o ControlMaster=no"

echo "Connecting to $ROBOT_HOST as $ROBOT_USER..."
prepare_connection
ssh_connect_enable_forwarding
make_port_forwarding
