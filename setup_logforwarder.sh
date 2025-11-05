#!/bin/bash
set -e

INSTALL_DIR="/opt/logforwarder"
SERVICE_FILE="/etc/systemd/system/waf_forwarder.service"
PYTHON_BIN="/usr/bin/python3"

echo "[+] Installing Log Forwarder..."

# Create directory
mkdir -p "$INSTALL_DIR"

# Create Python virtual environment
if [ ! -d "$INSTALL_DIR/venv" ]; then
    echo "[+] Creating Python virtual environment..."
    $PYTHON_BIN -m venv "$INSTALL_DIR/venv"
fi

source "$INSTALL_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null
deactivate

# =====================
# Create forwarder.conf
# =====================
cat > "$INSTALL_DIR/forwarder.conf" <<EOF
# Log Forwarder Configuration
# Input and output can be TCP or UDP
# Example: input_proto=udp, output_proto=tcp

input_host=0.0.0.0
input_port=514
input_proto=udp

output_host=127.0.0.1
output_port=12516
output_proto=tcp
EOF

# =====================
# Create forwarder.py
# =====================
cat > "$INSTALL_DIR/forwarder.py" <<'EOF'
#!/usr/bin/env python3
import socket
import sys
import os
from datetime import datetime

CONFIG_FILE = "/opt/logforwarder/forwarder.conf"

def log(msg):
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

def load_config():
    if not os.path.exists(CONFIG_FILE):
        log(f"[!] Config file not found: {CONFIG_FILE}")
        sys.exit(1)

    config = {}
    with open(CONFIG_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip()

    required = ["input_host", "input_port", "input_proto", "output_host", "output_port", "output_proto"]
    for key in required:
        if key not in config:
            log(f"[!] Missing required config key: {key}")
            sys.exit(1)

    config["input_port"] = int(config["input_port"])
    config["output_port"] = int(config["output_port"])
    return config

def forward_udp_to_tcp(cfg):
    udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp_sock.bind((cfg["input_host"], cfg["input_port"]))
    log(f"[+] Listening for UDP on {cfg['input_host']}:{cfg['input_port']} → forwarding to {cfg['output_proto'].upper()} {cfg['output_host']}:{cfg['output_port']}")

    while True:
        data, addr = udp_sock.recvfrom(65535)
        for logline in data.decode(errors="ignore").splitlines():
            if not logline.strip():
                continue
            try:
                with socket.create_connection((cfg["output_host"], cfg["output_port"])) as tcp_sock:
                    tcp_sock.sendall((logline.strip() + "\n").encode())
                log(f"[✓] Forwarded log from {addr[0]}")
            except Exception as e:
                log(f"[!] Error forwarding: {e}")

def main():
    cfg = load_config()

    if cfg["input_proto"].lower() == "udp" and cfg["output_proto"].lower() == "tcp":
        forward_udp_to_tcp(cfg)
    else:
        log("[!] Only UDP→TCP mode supported currently.")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

chmod +x "$INSTALL_DIR/forwarder.py"

# =====================
# Create systemd service
# =====================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=WAF Log Forwarder Service
After=network.target

[Service]
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/forwarder.py
Restart=always
User=root
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

# =====================
# Enable and Start
# =====================
systemctl daemon-reload
systemctl enable waf_forwarder.service
systemctl restart waf_forwarder.service

echo "[✓] Installation complete!"
echo "[→] Service: waf_forwarder.service"
EOF
