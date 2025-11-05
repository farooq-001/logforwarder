#!/bin/bash
# --------------------------------------------------------------------
# Dynamic Log Forwarder Installer (with Virtual Environment)
# --------------------------------------------------------------------

set -e

INSTALL_DIR="/opt/logforwarder"
VENV_DIR="$INSTALL_DIR/venv"
SERVICE_FILE="/etc/systemd/system/logforwarder.service"
PYTHON_BIN="/usr/bin/python3"

echo "[+] Creating installation directories..."
sudo mkdir -p $INSTALL_DIR

echo "[+] Creating Python virtual environment..."
sudo $PYTHON_BIN -m venv $VENV_DIR

echo "[+] Activating virtual environment and upgrading pip..."
sudo $VENV_DIR/bin/pip install --upgrade pip >/dev/null 2>&1

echo "[+] Creating configuration file..."
sudo tee $INSTALL_DIR/forwarder.conf > /dev/null <<'EOF'
{
    "input_host": "0.0.0.0",
    "input_port": 514,
    "input_proto": "udp",
    "output_host": "127.0.0.1",
    "output_port": 12516,
    "output_proto": "tcp"
}
EOF

echo "[+] Creating Python forwarder script..."
sudo tee $INSTALL_DIR/forwarder.py > /dev/null <<'EOF'
#!/usr/bin/env python3
import socket
import sys
import json
import os
from datetime import datetime

CONFIG_FILE = "/opt/logforwarder/forwarder.conf"

def log(msg):
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

def load_config():
    if not os.path.exists(CONFIG_FILE):
        log(f"[!] Config file not found: {CONFIG_FILE}")
        sys.exit(1)
    with open(CONFIG_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            log("[!] Invalid JSON in config file.")
            sys.exit(1)

def create_input_socket(proto, host, port):
    if proto.lower() == "udp":
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind((host, port))
        log(f"[+] Listening on UDP {host}:{port}")
    elif proto.lower() == "tcp":
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((host, port))
        sock.listen(5)
        log(f"[+] Listening on TCP {host}:{port}")
    else:
        log("[!] Unsupported input protocol. Use 'udp' or 'tcp'.")
        sys.exit(1)
    return sock

def send_output(proto, host, port, message):
    try:
        if proto.lower() == "udp":
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.sendto(message.encode(), (host, port))
            log(f"[→] Sent UDP log to {host}:{port}")
        elif proto.lower() == "tcp":
            with socket.create_connection((host, port), timeout=3) as s:
                s.sendall((message + "\n").encode())
            log(f"[→] Sent TCP log to {host}:{port}")
    except Exception as e:
        log(f"[!] Output send error to {host}:{port} — {e}")

def udp_forwarder(cfg):
    sock = create_input_socket("udp", cfg["input_host"], cfg["input_port"])
    log(f"[=] Forwarding UDP → {cfg['output_proto'].upper()} {cfg['output_host']}:{cfg['output_port']}")
    while True:
        data, addr = sock.recvfrom(65535)
        log(f"[←] Received UDP packet from {addr[0]}:{addr[1]}")
        for line in data.decode(errors="ignore").strip().splitlines():
            if line.strip():
                send_output(cfg["output_proto"], cfg["output_host"], cfg["output_port"], line.strip())

def tcp_forwarder(cfg):
    sock = create_input_socket("tcp", cfg["input_host"], cfg["input_port"])
    log(f"[=] Forwarding TCP → {cfg['output_proto'].upper()} {cfg['output_host']}:{cfg['output_port']}")
    while True:
        conn, addr = sock.accept()
        log(f"[+] New TCP connection from {addr[0]}:{addr[1]}")
        with conn:
            while True:
                data = conn.recv(65535)
                if not data:
                    log(f"[-] TCP client disconnected: {addr[0]}:{addr[1]}")
                    break
                for line in data.decode(errors="ignore").strip().splitlines():
                    if line.strip():
                        send_output(cfg["output_proto"], cfg["output_host"], cfg["output_port"], line.strip())

def main():
    cfg = load_config()
    log(f"[#] Loaded configuration: {cfg}")
    if cfg["input_proto"].lower() == "udp":
        udp_forwarder(cfg)
    elif cfg["input_proto"].lower() == "tcp":
        tcp_forwarder(cfg)
    else:
        log("[!] Invalid input protocol in config file (use 'udp' or 'tcp').")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("[!] Stopped by user.")
        sys.exit(0)
EOF

sudo chmod +x $INSTALL_DIR/forwarder.py

echo "[+] Creating systemd service..."
sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=Dynamic Log Forwarder (with Python venv)
After=network.target

[Service]
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/forwarder.py
Restart=always
RestartSec=3
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Reloading systemd daemon..."
sudo systemctl daemon-reload
sudo systemctl enable logforwarder
sudo systemctl restart logforwarder

echo "[✓] Log Forwarder successfully installed and running!"
echo "[→] View logs: sudo journalctl -u logforwarder -f"
echo "[→] Edit config: sudo nano $INSTALL_DIR/forwarder.conf"
