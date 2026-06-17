# Stoat Self‑Hosted on LAN with Self‑Signed TLS

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [SSH Access to the VM](#ssh-access-to-the-vm)
  - [Install and enable SSH server on the VM](#install-and-enable-ssh-server-on-the-vm)
  - [Create or use an SSH key (client)](#create-or-use-an-ssh-key-client)
  - [Connect from Linux or macOS](#connect-from-linux-or-macos)
  - [Connect from Windows (PowerShell / OpenSSH)](#connect-from-windows-powershell--openssh)
  - [Connect from Windows (PuTTY)](#connect-from-windows-putty)
  - [Verify and troubleshoot](#verify-and-troubleshoot)
- [Configure a Static Local IP on Ubuntu](#configure-a-static-local-ip-on-ubuntu)
  - [Option A — Netplan (recommended for Ubuntu server)](#option-a--netplan-recommended-for-ubuntu-server)
  - [Option B — NetworkManager (desktop or systems using NM)](#option-b--networkmanager-desktop-or-systems-using-nm)
  - [Option C — Legacy /etc/network/interfaces (older systems)](#option-c--legacy-etcnetworkinterfaces-older-systems)
  - [Option D — Router DHCP reservation (recommended alternative)](#option-d--router-dhcp-reservation-recommended-alternative)
- [Verify Static IP and SSH Reachability](#verify-static-ip-and-ssh-reachability)
  - [Quick checklist before you finish](#quick-checklist-before-you-finish)
  - [Example variables to replace in the examples](#example-variables-to-replace-in-the-examples)
- [Quick install script](#quick-install-script)
- [What the script does](#what-the-script-does)
- [Certificate distribution and import](#certificate-distribution-and-import)
  - [Copy certificate from server via SSH or SCP](#copy-certificate-from-server-via-ssh-or-scp)
  - [Import certificate on Windows](#import-certificate-on-windows)
    - [Delete imported certificate on Windows](#delete-imported-certificate-on-windows)
  - [Import certificate on Linux](#import-certificate-on-linux)
    - [Delete imported certificate on Linux](#delete-imported-certificate-on-linux)
  - [Import certificate on macOS](#import-certificate-on-macos)
    - [Delete imported certificate on macOS](#delete-imported-certificate-on-macos)
- [Add hostname to hosts file](#add-hostname-to-hosts-file)
  - [Windows hosts file edit PowerShell](#windows-hosts-file-edit-powershell)
  - [Linux and macOS hosts file edit](#linux-and-macos-hosts-file-edit)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Reset and cleanup](#reset-and-cleanup)
- [Notes](#notes)
- [Hyper-V VM LAN Access Without Internet](#hyper-v-vm-lan-access-without-internet)
---

## Overview

This README explains how to install Stoat on a single Ubuntu VM for LAN use with a self‑signed certificate. First run the `setup-stoat.sh` installer script. The script auto‑detects the server IP from the specified network interface (default `eth0`), generates a SAN self‑signed certificate, installs Docker and Compose plugin if missing, runs `generate_config.sh --overwrite <HOSTNAME>`, and brings the stack up with `docker compose up -d`.

---

## Prerequisites

- Ubuntu server with `sudo` access.  
- Primary network interface (default `eth0`) or pass the correct interface name to the installer script.  
- Ports opened in your network/firewall for LAN use: **80/tcp**, **443/tcp**, **7881/tcp**, and **50000–50100/udp**.  
- You will run the installer script with `sudo`.

---

## SSH Access to the VM

### Install and enable SSH server on the VM
```bash
# Install OpenSSH server
sudo apt update
sudo apt install -y openssh-server

# Ensure SSH is enabled and running
sudo systemctl enable --now ssh

# Allow SSH through UFW firewall
sudo ufw allow ssh
sudo ufw reload

# Verify SSH is listening
ss -ltnp | grep ssh
```

### Create or use an SSH key (client)
```bash
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy public key to the VM (replace user@vm)
ssh-copy-id user@VM_IP
# fallback if ssh-copy-id not available
cat ~/.ssh/id_ed25519.pub | ssh user@VM_IP 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'
```

### Connect from Linux or macOS
```bash
ssh user@VM_IP
# if you used a nonstandard key or port:
ssh -i ~/.ssh/id_ed25519 -p 2222 user@VM_IP
```

### Connect from Windows (PowerShell / OpenSSH)
```powershell
# From PowerShell (Windows 10+ with OpenSSH)
ssh user@VM_IP
```

### Connect from Windows (PuTTY)
- Open PuTTY, set **Host Name** to `user@VM_IP`, set **Port** if nonstandard, load your private key via **Connection → SSH → Auth → Private key file for authentication**, then **Open**.

### Verify and troubleshoot
```bash
# From the VM: show authorized keys and SSH status
sudo cat /var/log/auth.log | tail -n 50
sudo systemctl status ssh

# From client: verbose SSH output
ssh -vvv user@VM_IP
```

---

## Configure a Static Local IP on Ubuntu

> Use the method that matches your system: **Netplan** (Ubuntu 18.04+ server), **NetworkManager** (desktop), or legacy `/etc/network/interfaces`. Replace `eth0`, `VM_IP`, `GATEWAY`, and `NAMESERVERS` with your values.

### Option A — Netplan (recommended for Ubuntu server)
```yaml
# Create or edit /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.1.x/24
      gateway4: 192.168.1.1
      nameservers:
        addresses: [192.168.1.1, 1.1.1.1]
```
```bash
# Apply the config
sudo netplan try
# If OK, make it permanent
sudo netplan apply

# Verify
ip -4 addr show eth0
ip route show
```

### Option B — NetworkManager (desktop or systems using NM)
```bash
# Set static IP with nmcli
nmcli connection modify "Wired connection 1" ipv4.addresses 192.168.1.x/24
nmcli connection modify "Wired connection 1" ipv4.gateway 192.168.1.1
nmcli connection modify "Wired connection 1" ipv4.dns "192.168.1.1 1.1.1.1"
nmcli connection modify "Wired connection 1" ipv4.method manual
nmcli connection up "Wired connection 1"
```

### Option C — Legacy /etc/network/interfaces (older systems)
```bash
# Edit /etc/network/interfaces
auto eth0
iface eth0 inet static
  address 192.168.1.x
  netmask 255.255.255.0
  gateway 192.168.1.1
  dns-nameservers 192.168.1.1 1.1.1.1

# Restart networking
sudo systemctl restart networking
# or
sudo ifdown eth0 && sudo ifup eth0
```

### Option D — Router DHCP reservation (recommended alternative)
- Log into your router's admin UI and create a DHCP reservation for the VM's MAC address. This keeps the VM on DHCP while ensuring a stable IP without changing OS network config.

---

## Verify Static IP and SSH Reachability

```bash
# From the VM
ip addr show eth0
ip route show
systemctl status ssh

# From another machine on the LAN
ping -c 3 192.168.1.x
ssh user@192.168.1.x
```

---

### Quick checklist before you finish
- **Confirm interface name** (`ip link`) and use it instead of `eth0` if different.  
- **Backup** existing network config files before editing.  
- **If remote**: schedule a fallback (console access or temporary DHCP) in case the static config prevents SSH access.  
- **Update /etc/hosts** on clients or local DNS so `stoat.local` resolves to the static IP.  

---

### Example variables to replace in the examples
- `eth0` → your network interface name  
- `192.168.1.x` → desired static IP (`VM_IP`)  
- `192.168.1.1` → gateway/router IP (`GATEWAY`)  
- `1.1.1.1` → alternate DNS resolver


## Quick install script

```bash
sudo chmod +x setup-stoat.sh
sudo ./setup-stoat.sh stoat.local eth0
```

Arguments:
- **hostname** (default `stoat.local`)  
- **network interface** to probe for the VM IP (default `eth0`)

---

## What the script does

- Detects the server IP from the specified interface (fallback to first non‑loopback IP).  
- Updates the system and installs prerequisites (curl, git, openssl, etc.).  
- Installs Docker Engine and the Compose plugin if missing.  
- Generates a SAN config and a self‑signed certificate placed in `/etc/ssl/stoat`.  
- Runs `generate_config.sh --overwrite <HOSTNAME>`.
- Pulls images and brings the stack up with `docker compose up -d`.

---

## Certificate distribution and import

After the server generates **`/etc/ssl/stoat/stoat.local.crt`** you must copy and import it on client machines so browsers trust the site.

### Copy certificate from server via SSH or SCP

**From your workstation (Linux/macOS):**
```bash
# copy certificate to current directory
scp user@server:/etc/ssl/stoat/stoat.local.crt .
```

**If you only have SSH and want to print the cert locally:**
```bash
ssh user@server 'sudo cat /etc/ssl/stoat/stoat.local.crt' > stoat.local.crt
```

**From Windows (PowerShell with OpenSSH installed):**
```powershell
scp user@server:/etc/ssl/stoat/stoat.local.crt .
```

---

### Import certificate on Windows

**Method A GUI**
1. Copy **`stoat.local.crt`** to the Windows machine.  
2. Double‑click the `.crt` file → click **Install Certificate** → choose **Local Machine** → **Place all certificates in the following store** → **Browse** → select **Trusted Root Certification Authorities** → Finish.  
3. Restart the browser.

**Method B PowerShell (run as Administrator)**
1. **Set the certificate path**
```powershell
$certPath = "C:\path\to\stoat.local.crt"
```
2. **Recommended (PowerShell native)**
```powershell
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\Root
```
3. **Alternative (certutil)**
```powershell
certutil -addstore -f "Root" $certPath
```

#### Delete imported certificate on Windows

**Find the certificate (PowerShell, run as Administrator)**
```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*stoat.local*" } | Format-List Thumbprint,Subject
```
**Remove by thumbprint (PowerShell)**
```powershell
$thumb = "<THUMBPRINT_FROM_PREVIOUS_COMMAND>"
Remove-Item -Path "Cert:\LocalMachine\Root\$thumb" -Confirm:$false
```
**Or remove with certutil**
```powershell
certutil -delstore "Root" <THUMBPRINT>
```
**Or GUI**
- Open **mmc.exe** → File → Add/Remove Snap-in → **Certificates** → **Computer account** → **Local computer** → OK.  
- Browse **Trusted Root Certification Authorities** → **Certificates** → find **stoat.local** → right‑click → **Delete**.  
- Restart the browser.

---

### Import certificate on Linux

**System trust (Debian/Ubuntu)**
```bash
# copy cert to system CA directory
sudo cp stoat.local.crt /usr/local/share/ca-certificates/stoat.local.crt
# update CA store
sudo update-ca-certificates
```

**RHEL/CentOS (alternatives)**
```bash
# copy to anchors and update trust
sudo cp stoat.local.crt /etc/pki/ca-trust/source/anchors/stoat.local.crt
sudo update-ca-trust extract
```

#### Delete imported certificate on Linux

**Debian/Ubuntu**
```bash
# remove the file you added and update CA store
sudo rm /usr/local/share/ca-certificates/stoat.local.crt
sudo update-ca-certificates --fresh
```
**RHEL/CentOS**
```bash
sudo rm /etc/pki/ca-trust/source/anchors/stoat.local.crt
sudo update-ca-trust extract
```
**Notes**
- After removal, restart browsers and any services that cache the system CA store.

---

### Import certificate on macOS

**Using Keychain Access**
1. Copy **`stoat.local.crt`** to the Mac.  
2. Open **Keychain Access** → select **System** keychain → File → Import Items → choose **`stoat.local.crt`**.  
3. Find the imported cert → double‑click → **Trust** → **When using this certificate** → **Always Trust**.  
4. Restart the browser.

**Command line (requires sudo)**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /path/to/stoat.local.crt
```

#### Delete imported certificate on macOS

**GUI (Keychain Access)**
- Open **Keychain Access** → select **System** keychain → search for **stoat.local** → right‑click the certificate → **Delete**.  
- Restart the browser.

**Command line**
```bash
# delete by common name
sudo security delete-certificate -c "stoat.local" -k /Library/Keychains/System.keychain
```
**If you need to locate the certificate fingerprint first**
```bash
security find-certificate -a -c "stoat.local" -Z /Library/Keychains/System.keychain
# then delete by SHA-1 hash
sudo security delete-certificate -Z <SHA1_HASH> /Library/Keychains/System.keychain
```

---

## Add hostname to hosts file

Clients must resolve **`stoat.local`** to the VM IP. Add an entry to the hosts file on each client.

### Windows hosts file edit PowerShell

**Run as Administrator**:

```powershell
$ip = "<VM_IP>"   # replace with your VM IP
$host = "stoat.local"
$entry = "$ip`t$host"
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
# add only if not present
if (-not (Select-String -Path $hostsPath -Pattern $host -Quiet)) {
  Add-Content -Path $hostsPath -Value $entry
}
```

Or manually edit `C:\Windows\System32\drivers\etc\hosts` with Notepad run as Administrator and add:
```
<VM_IP> stoat.local
```

### Linux and macOS hosts file edit

```bash
VM_IP="<VM_IP>"   # replace with detected VM IP
HOSTNAME="stoat.local"
# add only if not present
if ! grep -q "$HOSTNAME" /etc/hosts; then
  echo "${VM_IP} ${HOSTNAME}" | sudo tee -a /etc/hosts
fi
```

---

## Verification

```bash
# Check containers
sudo docker compose ps

# Test HTTPS from the host
curl -vk https://stoat.local/
openssl s_client -connect ${VM_IP}:443 -servername stoat.local -showcerts

```

Open a browser to `https://stoat.local`, accept or import the self‑signed certificate, and test joining a voice channel.

---

## Troubleshooting

- **Browser still warns**: ensure the certificate is imported into the correct trust store (Windows system store, macOS System keychain, or Linux CA store).  
- **Hosts not resolving**: verify `/etc/hosts` or Windows hosts file contains the correct mapping and flush DNS cache if needed.  
  - Windows flush DNS: `ipconfig /flushdns` (run as Administrator).  
  - macOS flush DNS: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.  
- **Firewall**: confirm UFW rules allow required ports.  
- **Docker issues**: restart Docker `sudo systemctl restart docker` and re-run `docker compose up -d`.

---

## Reset and cleanup

```bash
# Stop and remove Stoat compose services
sudo docker compose down

# Remove all containers (destructive)
#docker rm -f $(docker ps -aq)

# Remove images and volumes (destructive)
#docker rmi -f $(docker images -aq)
#docker volume rm $(docker volume ls -q) || true

```

---

## Notes

- If your primary network interface is not `eth0`, pass the correct interface name to the installer script or edit the script accordingly.

## Hyper-V VM LAN Access Without Internet

1. Create an External switch (Hyper‑V Manager → Virtual Switch Manager → External)
2. Attach the VM's network adapter to that External switch. 
3. Block Internet while keeping LAN access: the recommended host-side option is a Hyper‑V network ACL that denies traffic to your gateway/WAN IP but allows other LAN subnets. Use Add-VMNetworkAdapterAcl to deny the gateway IP for that VM:
```powershell
Add-VMNetworkAdapterAcl -VMName "MyVM" -RemoteIPAddress 192.168.1.1 -Direction Both -Action Deny
Get-VMNetworkAdapterAcl -VMName "MyVM"
```