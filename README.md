# logforwarder

🛰️ Log Forwarder

A lightweight and dynamic Python-based log forwarder for Linux.
It can receive logs over UDP or TCP and forward them to any destination using UDP or TCP.
Designed for syslog, Nginx, WAF, or custom log pipelines (e.g., Logstash).

⚙️ Features

Cross-distribution compatible (Ubuntu, Debian, CentOS, RHEL, Rocky, Fedora)

Supports UDP → TCP forwarding (default)

Dynamic configuration via forwarder.conf

Auto-starts on boot via systemd

Python virtual environment support

Minimal CPU and memory usage

📦 Installation

Run this command to install automatically:

curl -sSL https://raw.githubusercontent.com/farooq-001/logforwarder/master/setup_logforwarder.sh | bash
