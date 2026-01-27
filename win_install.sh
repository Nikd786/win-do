#!/bin/bash
#
# DIGITALOCEAN INSTALLER - FINAL STABLE VERSION
# Fixes: Auto-close CMD, Universal Desktop Path, No-Interaction Setup
#

# --- LOGGING FUNCTIONS ---
function log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
function log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
function log_error() { echo -e "\e[31m[ERROR]\e[0m $1"; }
function log_step() { echo -e "\n\e[33m>>> $1 \e[0m"; }

clear
echo "===================================================="
echo "   WINDOWS INSTALLER - AUTO-CLOSE & FIX DESKTOP     "
echo "===================================================="

# --- 1. INSTALL DEPENDENCIES ---
log_step "STEP 1: Installing Dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y ntfs-3g parted psmisc curl wget jq || { log_error "Failed to install tools"; exit 1; }

# --- 2. DOWNLOAD CHROME ---
log_step "STEP 2: Pre-downloading Chrome"
wget -q --show-progress --progress=bar:force -O /tmp/chrome.msi "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"

# --- 3. OS SELECTION ---
log_step "STEP 3: Select Operating System"
echo "  1) Windows 2019 (Cloudflare R2 Recommended)"
echo "  2) Windows 2019 (Mediafire [Faster])"
echo "  3) Windows 10 Super Lite"
echo "  4) Custom Link"
read -p "Select [1]: " PILIHOS

case "$PILIHOS" in
  1|"") PILIHOS="https://pub-24c03f7a3eff4fa6936c33e2474d6905.r2.dev/windows2019DO.gz";;
  2) PILIHOS="https://download1531.mediafire.com/7s5hm4ft5pgghcgdywbqMd3OA6I2kY-Lk_VpClDf7uYC1I4QOvz_xTGVhMeGkdxyT8FJxvzoiqGlWmMUWsKv-MDSw36CiDTF-i-HCt4hBlG_1QdpZYMSAiowYc8LZw_4V0mtW6QF--iBBxAMt8sluAUgR_HUf3sZ_PNNS-V5FPH1n4c/5467b14n86t47b0/windows2019.gz";;
  3) PILIHOS="https://umbel.my.id/wedus10lite.gz";;
  4) read -p "Enter Direct Link: " PILIHOS;;
  *) PILIHOS="https://pub-24c03f7a3eff4fa6936c33e2474d6905.r2.dev/windows2019DO.gz";;
esac

# --- 4. NETWORK DETECTION ---
log_step "STEP 4: Calculating Network Settings"
RAW_DATA=$(ip -4 -o addr show | awk '{print $4}' | grep -v "^10\." | grep -v "^127\." | head -n1)
CLEAN_IP=${RAW_DATA%/*}
CLEAN_PREFIX=${RAW_DATA#*/}
GW=$(ip route | awk '/default/ { print $3 }' | head -n1)

case "$CLEAN_PREFIX" in
    8) SUBNET_MASK="255.0.0.0";;
    16) SUBNET_MASK="255.255.0.0";;
    24) SUBNET_MASK="255.255.255.0";;
    *) SUBNET_MASK="255.255.255.0";;
esac

# --- 5. GENERATE BATCH FILE ---
log_step "STEP 5: Generating Windows Setup Script"

cat > /tmp/win_setup.bat << 'EOFBATCH'
@ECHO OFF
SETLOCAL EnableDelayedExpansion
SET IP=PLACEHOLDER_IP
SET MASK=PLACEHOLDER_MASK
SET GW=PLACEHOLDER_GW

net session >nul 2>&1
if %errorLevel% NEQ 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

ECHO [LOG] Config Network...
timeout /t 10 /nobreak >nul

SET ADAPTER_NAME=
netsh interface show interface name="Ethernet Instance 0" >nul 2>&1
if %errorlevel% EQU 0 (SET "ADAPTER_NAME=Ethernet Instance 0") else (
    for /f "tokens=3*" %%a in ('netsh interface show interface ^| findstr /C:"Connected"') do (SET "ADAPTER_NAME=%%b" & goto :found)
)
:found
netsh interface ip set address name="%ADAPTER_NAME%" source=static addr=%IP% mask=%MASK% gateway=%GW% gwmetric=1
netsh interface ip set dns name="%ADAPTER_NAME%" source=static addr=8.8.8.8
netsh interface ip add dns name="%ADAPTER_NAME%" addr=8.8.4.4 index=2

ECHO [LOG] Extending Disk...
(echo select disk 0 & echo select partition 2 & echo extend) > C:\dp.txt
diskpart /s C:\dp.txt >nul 2>&1 & del C:\dp.txt

ECHO [LOG] Enabling RDP...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >nul
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes >nul

if exist "C:\chrome.msi" (
    ECHO [LOG] Install Chrome...
    start /wait msiexec /i "C:\chrome.msi" /quiet /norestart
    del /f /q C:\chrome.msi
)

ECHO ===========================================
ECHO      SETUP COMPLETE - AUTO CLOSE IN 5s
ECHO ===========================================
timeout /t 5 /nobreak >nul
(goto) 2>nul & del "%~f0" & exit
EOFBATCH

sed -i "s/PLACEHOLDER_IP/$CLEAN_IP/g" /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_MASK/$SUBNET_MASK/g" /tmp/win_setup.bat
sed -i "s/PLACEHOLDER_GW/$GW/g" /tmp/win_setup.bat

# --- 6. WRITE IMAGE ---
log_step "STEP 6: Writing OS to Disk (This takes time...)"
umount -f /dev/vda* 2>/dev/null
wget --no-check-certificate -O- "$PILIHOS" | gunzip | dd of=/dev/vda bs=4M status=progress
sync

# --- 7. MOUNT ---
log_step "STEP 7: Mounting Windows"
partprobe /dev/vda
sleep 5
TARGET="/dev/vda2"
[ -b "/dev/vda1" ] && [ ! -b "/dev/vda2" ] && TARGET="/dev/vda1"
mkdir -p /mnt/windows
mount.ntfs-3g -o force,rw "$TARGET" /mnt/windows

# --- 8. INJECT FILES ---
log_step "STEP 8: Injecting Files"
# Path Startup & Public Desktop
PATH_STARTUP="/mnt/windows/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup"
PATH_PUBLIC_DESKTOP="/mnt/windows/Users/Public/Desktop"

mkdir -p "$PATH_STARTUP" "$PATH_PUBLIC_DESKTOP"

# Create GantiPassword.bat
cat > /tmp/GantiPass.bat << 'EOF'
@echo off
net session >nul 2>&1
if %errorLevel% neq 0 (echo [!] Klik Kanan > Run As Administrator & pause & exit)
echo ========================================
echo        GANTI PASSWORD WINDOWS
echo ========================================
set /p "np=Masukkan Password Baru: "
net user Administrator %np%
net user %username% %np%
echo [OK] Selesai! Menutup dalam 3 detik...
timeout /t 3 /nobreak >nul
exit
EOF

cp -f /tmp/win_setup.bat "$PATH_STARTUP/win_setup.bat"
cp -f /tmp/GantiPass.bat "$PATH_PUBLIC_DESKTOP/GantiPassword.bat"
cp -v /tmp/chrome.msi /mnt/windows/chrome.msi

log_success "Injected to Startup and Public Desktop."

# --- 9. FINISH ---
log_step "STEP 9: Cleaning Up"
sync
umount /mnt/windows
log_success "Done! Powering off..."
sleep 3
poweroff
