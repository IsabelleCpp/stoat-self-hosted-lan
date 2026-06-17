# Stoat Self‑Hosted on LAN with Self‑Signed TLS

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick install script](#quick-install-script)
- [What the script does](#what-the-script-does)
- [Certificate distribution and import](#certificate-distribution-and-import)
  - [Copy certificate from server via SSH or SCP](#copy-certificate-from-server-via-ssh-or-scp)
  - [Import certificate on Windows](#import-certificate-on-windows)
  - [Import certificate on Linux](#import-certificate-on-linux)
  - [Import certificate on macOS](#import-certificate-on-macos)
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

## Quick install script

```bash
sudo chmod +x setup-stoat.sh
sudo ./setup-stoat.sh /opt/stoat stoat.local eth0
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

After the server generates `/etc/ssl/stoat/stoat.local.crt` you must copy and import it on client machines so browsers trust the site.

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
1. Copy `stoat.local.crt` to the Windows machine.  
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

---

### Import certificate on Linux

**System trust (Debian/Ubuntu)**
```bash
# copy cert to system CA directory
sudo cp stoat.local.crt /usr/local/share/ca-certificates/stoat.local.crt
# update CA store
sudo update-ca-certificates
```

---

### Import certificate on macOS

**Using Keychain Access**
1. Copy `stoat.local.crt` to the Mac.  
2. Open **Keychain Access** → select **System** keychain → File → Import Items → choose `stoat.local.crt`.  
3. Find the imported cert → double‑click → **Trust** → **When using this certificate** → **Always Trust**.  
4. Restart the browser.

**Command line (requires sudo)**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /path/to/stoat.local.crt
```

---

## Add hostname to hosts file

Clients must resolve `stoat.local` to the VM IP. Add an entry to the hosts file on each client.

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
cd /opt/stoat
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