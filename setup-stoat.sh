#!/usr/bin/env bash
set -euo pipefail

# Defaults
HOSTNAME="stoat.local"
INTERFACE="eth0"
CERT_DIR="/etc/ssl/stoat"
SAN_CONF="$HOME/san.cnf"
COMPOSE_FILE="./compose.yml"
CADDYFILE="./Caddyfile"
GEN_SCRIPT="./generate_config.sh"
REGEN_CERT=0

usage() {
  cat <<EOF
Usage: $0 [HOSTNAME] [INTERFACE] [--regen-cert|-r] [--help]

Options:
  --regen-cert, -r   Force regeneration of the self-signed certificate
  --help             Show this help message
EOF
}

# Parse args (positional + flags)
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --regen-cert|-r)
      REGEN_CERT=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Apply positional args if provided
if [ ${#POSITIONAL[@]} -ge 1 ]; then
  HOSTNAME="${POSITIONAL[0]}"
fi
if [ ${#POSITIONAL[@]} -ge 2 ]; then
  INTERFACE="${POSITIONAL[1]}"
fi

echo "=== Stoat installer ==="
echo "Hostname: $HOSTNAME"
echo "Network interface: $INTERFACE"
if [ "$REGEN_CERT" -eq 1 ]; then
  echo "Certificate regeneration: enabled"
else
  echo "Certificate regeneration: disabled (will skip if cert exists)"
fi

# Detect IPv4 on interface, fallback to first non-loopback address
VM_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 || true)
if [ -z "$VM_IP" ]; then
  VM_IP=$(hostname -I | awk '{print $1}')
fi
if [ -z "$VM_IP" ]; then
  echo "ERROR: Could not detect an IP address. Please set VM_IP manually and re-run."
  exit 1
fi
echo "Detected VM IP: $VM_IP"

# Update and install prerequisites
echo "Updating system and installing prerequisites..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl git micro openssl apt-transport-https gnupg lsb-release

# Configure UFW (idempotent)
echo "Configuring UFW firewall rules..."
sudo ufw allow ssh || true
sudo ufw allow http || true
sudo ufw allow https || true
sudo ufw allow 7881/tcp || true
sudo ufw allow 50000:50100/udp || true
sudo ufw default deny incoming || true
sudo ufw --force enable || true

# Install Docker if missing
if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "Docker already installed"
fi

# Create CERT_DIR if needed
sudo mkdir -p "$CERT_DIR"
sudo chown root:root "$CERT_DIR"
sudo chmod 755 "$CERT_DIR"

CERT_KEY="${CERT_DIR}/${HOSTNAME}.key"
CERT_CRT="${CERT_DIR}/${HOSTNAME}.crt"

# Decide whether to generate certificate
generate_cert() {
  echo "Generating self-signed certificate with SAN for $HOSTNAME and $VM_IP..."
  cat > "$SAN_CONF" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_req
prompt = no
[dn]
CN = ${HOSTNAME}
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${HOSTNAME}
IP.1 = ${VM_IP}
EOF

  sudo openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout "${CERT_KEY}" \
    -out "${CERT_CRT}" \
    -days 3650 \
    -config "$SAN_CONF"

  sudo chmod 640 "${CERT_KEY}"
  sudo chown root:root "${CERT_KEY}" "${CERT_CRT}"
  echo "Certificate generated at ${CERT_CRT}"
}

if [ "$REGEN_CERT" -eq 1 ]; then
  echo "Forcing certificate regeneration..."
  generate_cert
else
  if [ -f "$CERT_KEY" ] && [ -f "$CERT_CRT" ]; then
    echo "Certificate and key already exist for ${HOSTNAME} in ${CERT_DIR}. Skipping generation."
  else
    generate_cert
  fi
fi

# Ensure generate_config.sh is executable
if [ -f "$GEN_SCRIPT" ]; then
  chmod +x "$GEN_SCRIPT"
else
  echo "ERROR: generate_config.sh not found"
  exit 1
fi

# Run generate_config.sh to produce config files
echo "Running generate_config.sh --overwrite $HOSTNAME ..."
./generate_config.sh --overwrite "$HOSTNAME" || true

# Pull and start containers
echo "Pulling images and starting Stoat stack..."
sudo docker compose pull || true
sudo docker compose up -d

echo "=== Done ==="
echo "Visit: https://${HOSTNAME} (accept or import the self-signed certificate)"
