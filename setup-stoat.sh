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

# Generate certificate with SAN
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

# Produce Base64 strings for Windows import and print quick commands
echo "Preparing Windows import commands..."

# DER encoded Base64 (recommended for Windows)
CERT_B64_DER=$(openssl x509 -in "$CERT_CRT" -outform der | base64 -w0)

# PEM body Base64 (alternative)
CERT_B64_PEM=$(awk 'BEGIN{ORS="";} /-----BEGIN CERTIFICATE-----/{p=1;next} /-----END CERTIFICATE-----/{p=0} p{print}' "$CERT_CRT" | base64 -w0)

echo
echo "=== Windows PowerShell one-line import command for LocalMachine Root ==="
echo "Paste the following line into an elevated PowerShell window (run as Administrator)."
echo "It will show which certificates would be deleted, ask for confirmation, then delete and import the new certificate."
echo

printf '%s\n\n' "\$hostName='${HOSTNAME}'; \$matches = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { \$_.Subject -like \"*\$hostName*\" -or \$_.Subject -like \"*CN=\$hostName*\" }; if (\$matches) { \$matches | Format-Table Subject,Thumbprint; \$ans = Read-Host 'Delete the above certificates? Type Y to confirm'; if (\$ans -match '^[Yy]$') { \$matches | Remove-Item -Force } else { Write-Host 'Deletion aborted by user'; } } else { Write-Host 'No matching certificates found in LocalMachine\\Root'; }; \$b='${CERT_B64_DER}'; \$tmp=[IO.Path]::Combine(\$env:TEMP, \"\$hostName.crt\"); [IO.File]::WriteAllBytes(\$tmp,[Convert]::FromBase64String(\$b)); Import-Certificate -FilePath \$tmp -CertStoreLocation Cert:\LocalMachine\Root; Remove-Item \$tmp -Force"

echo
echo "=== Alternative PFX import one-line (if you create a PFX on Linux) ==="
echo "This variant also shows matches and asks for confirmation before deleting them. Replace BASE64_PFX and PFXPASSWORD."
printf '%s\n\n' "\$hostName='${HOSTNAME}'; \$matches = Get-ChildItem Cert:\LocalMachine\My | Where-Object { \$_.Subject -like \"*\$hostName*\" -or \$_.Subject -like \"*CN=\$hostName*\" }; if (\$matches) { \$matches | Format-Table Subject,Thumbprint; \$ans = Read-Host 'Delete the above certificates? Type Y to confirm'; if (\$ans -match '^[Yy]$') { \$matches | Remove-Item -Force } else { Write-Host 'Deletion aborted by user'; } } else { Write-Host 'No matching certificates found in LocalMachine\\My'; }; \$b='BASE64_PFX'; \$pw='PFXPASSWORD'; \$tmp=[IO.Path]::Combine(\$env:TEMP, \"\$hostName.pfx\"); [IO.File]::WriteAllBytes(\$tmp,[Convert]::FromBase64String(\$b)); Import-PfxCertificate -FilePath \$tmp -CertStoreLocation Cert:\LocalMachine\My -Password (ConvertTo-SecureString \$pw -AsPlainText -Force); Remove-Item \$tmp -Force"

echo
echo "=== Base64 strings produced on this machine ==="
echo "DER encoded Base64 (recommended for Windows import):"
echo
echo "${CERT_B64_DER}"
echo
echo "PEM body Base64 (alternative):"
echo
echo "${CERT_B64_PEM}"
echo

echo "=== Quick notes ==="
echo "• Run the one-line PowerShell commands as Administrator to modify LocalMachine stores."
echo "• The PowerShell one-liner lists matching certificates and requires you to type 'Y' to proceed with deletion."
echo "• The certificate is written to a proper temp file in the Windows temp directory and removed after import."
echo "• If you prefer to inspect matches first without deleting, run in an elevated PowerShell:"
echo "  Get-ChildItem Cert:\\LocalMachine\\Root | Where-Object { \$_.Subject -like '*${HOSTNAME}*' -or \$_.Subject -like '*CN=${HOSTNAME}*' } | Format-List Subject,Thumbprint"
echo "• To import a PFX (certificate + private key), create a PFX on the Linux side and base64 it; then use the PFX one-liner above with a secure password."
echo

echo "=== Done ==="
echo "Visit: https://${HOSTNAME} (accept or import the self-signed certificate)"
