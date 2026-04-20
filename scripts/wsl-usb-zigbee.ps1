# scripts/wsl-usb-zigbee.ps1
# Attaches Sonoff Zigbee 3.0 USB Dongle Plus V2 to WSL2 via usbipd.
# Matches by VID:PID so it survives USB port changes.
# Runs persistently with --auto-attach to re-attach on disconnect.
#
# SETUP (run once from elevated PowerShell):
#
#   $Action = New-ScheduledTaskAction `
#       -Execute "powershell.exe" `
#       -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"\\wsl.localhost\Ubuntu-20.04\home\jmendoza\homelab\scripts\wsl-usb-zigbee.ps1`""
#
#   $Trigger = New-ScheduledTaskTrigger -AtLogon
#   $Principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -RunLevel Highest -LogonType Interactive
#   $Settings = New-ScheduledTaskSettingsSet `
#       -ExecutionTimeLimit (New-TimeSpan) `
#       -AllowStartIfOnBatteries `
#       -DontStopIfGoingOnBatteries
#
#   Register-ScheduledTask `
#       -TaskName "Zigbee USB to WSL" `
#       -Action $Action `
#       -Trigger $Trigger `
#       -Principal $Principal `
#       -Settings $Settings `
#       -Force

$VidPid = "10c4:ea60"
$WslDistro = "Ubuntu-20.04"

usbipd attach --wsl $WslDistro --hardware-id $VidPid --auto-attach
