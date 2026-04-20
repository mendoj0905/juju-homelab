# scripts/wsl-ssh-portforward.ps1
# Run as a Windows Scheduled Task at logon to keep WSL SSH port forwarding working.
# Forwards Windows port 2222 to WSL2 port 22.

$WslIp = (wsl hostname -I).Trim().Split(" ")[0]

if (-not $WslIp) {
    Write-Error "Could not determine WSL IP. Is WSL running?"
    exit 1
}

Write-Output "WSL IP: $WslIp"

# Remove old rule
netsh interface portproxy delete v4tov4 listenport=2222 listenaddress=0.0.0.0 2>$null

# Add new rule
netsh interface portproxy add v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=22 connectaddress=$WslIp

Write-Output "Port forward set: 0.0.0.0:2222 -> ${WslIp}:22"

# Verify
netsh interface portproxy show v4tov4
