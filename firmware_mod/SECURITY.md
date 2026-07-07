# Security Notes

## Default Credentials

**CRITICAL**: The camera comes with well-known default credentials:

| Service | Username | Password |
|---------|----------|----------|
| SSH (dropbear) | root | ismart12 |
| WiFi AP (hostapd) | - | ismart12 |

## Recommended Security Steps

### 1. Change Default Password
```sh
/system/sdcard/scripts/passwd.sh
```

### 2. Use SSH Key Authentication
Copy your SSH public key to the camera:
```sh
ssh-copy-id -i ~/.ssh/id_rsa.pub root@<camera-ip>
```

Then disable password auth:
```sh
# Edit /system/sdcard/config/ssh.conf
ssh_password=off
```

### 3. Disable Telnet
Telnet is disabled by default. If you need it for debugging:
```sh
# Edit /system/sdcard/config/system.conf
TELNET=on
```

### 4. Secure WiFi
If using hostapd (access point mode):
- Change `wpa_passphrase` in `/system/sdcard/config/hostapd.conf`
- Use WPA2 (default) or WPA3 if supported

### 5. Network Security
- Use static IP or DHCP with reserved address
- Consider firewall rules if camera is internet-accessible
- Use VPN for remote access instead of port forwarding

### 6. Disable Unnecessary Services
Check `/system/sdcard/config/autostart/` and disable services you don't use:
```sh
rm /system/sdcard/config/autostart/<service>
```

## Reporting Security Issues

If you find a security vulnerability, please report it responsibly.
