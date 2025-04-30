#!/bin/bash
set -e

# --- Functions ---
install_if_missing() {
    for pkg in "$@"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            echo "Installing: $pkg"
            sudo pacman -S --noconfirm --needed "$pkg"
        else
            echo "Already installed: $pkg"
        fi
    done
}

enable_service() {
    local svc="$1"
    if ! systemctl is-enabled --quiet "$svc"; then
        echo "Enabling service: $svc"
        sudo systemctl enable "$svc"
    else
        echo "Service already enabled: $svc"
    fi
}

# --- Step 1: Update the system ---
echo ">> Updating system..."
sudo pacman -Syu --noconfirm

# --- Step 2: Add Surface Linux repo ---
if ! grep -q "\[linux-surface\]" /etc/pacman.conf; then
    echo ">> Adding Surface Linux repository..."
    curl -s https://raw.githubusercontent.com/linux-surface/linux-surface/main/pkg/keys/surface.asc | sudo pacman-key --add -
    sudo pacman-key --lsign-key 56C464BAAC421453
    echo -e "\n[linux-surface]\nServer = https://pkg.surfacelinux.com/arch/" | sudo tee -a /etc/pacman.conf
    sudo pacman -Sy
else
    echo ">> Surface repo already present."
fi

# --- Step 3: Install Surface kernel + tools ---
install_if_missing linux-surface linux-surface-headers iptsd libwacom-surface surface-control surface-dtx-daemon

# --- Step 4: Core system packages ---
install_if_missing \
    sof-firmware intel-media-driver mesa vulkan-intel \
    pipewire wireplumber pipewire-alsa pipewire-pulse pipewire-jack alsa-utils \
    tlp thermald powertop \
    bluez bluez-utils \
    cups system-config-printer sane sane-airscan \
    libwacom xf86-input-libinput xorg-xinput \
    plasma-wayland-session xdg-desktop-portal-kde qt6-wayland \
    dolphin konsole ark spectacle kate okular kdeconnect partitionmanager \
    iio-sensor-proxy xrandr xinput

# --- Step 5: Enable services ---
enable_service NetworkManager
enable_service bluetooth
enable_service cups
enable_service tlp
enable_service thermald
enable_service iptsd
enable_service surface-dtx-daemon
enable_service iio-sensor-proxy

# --- Step 6: Auto-rotation setup ---
cat << 'EOF' > ~/.config/autorotate.sh
#!/bin/bash

ORIENTATION=$(monitor-sensor --once | grep orientation | awk '{print $2}')
case "$ORIENTATION" in
  normal)
    xrandr --output eDP-1 --rotate normal
    xinput set-prop "libinput Accelerometer /dev/iio:device0 Sensor" "Coordinate Transformation Matrix" 1 0 0 0 1 0 0 0 1
    ;;
  bottom-up)
    xrandr --output eDP-1 --rotate inverted
    ;;
  left-up)
    xrandr --output eDP-1 --rotate left
    ;;
  right-up)
    xrandr --output eDP-1 --rotate right
    ;;
esac
EOF

chmod +x ~/.config/autorotate.sh

# Autostart it in Plasma
mkdir -p ~/.config/autostart
cat << 'EOF' > ~/.config/autostart/autorotate.desktop
[Desktop Entry]
Type=Application
Exec=/home/$USER/.config/autorotate.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Auto Rotate
EOF

# --- Step 7: Set HiDPI scaling for Plasma ---
mkdir -p ~/.config
cat << EOF > ~/.config/kcmfonts
[General]
forceFontDPI=192
EOF

echo ">> HiDPI scaling set to 200% (192 DPI). Adjust later in System Settings → Fonts if needed."

# --- Step 8: Stylus button remap (eraser mode for barrel button) ---
mkdir -p ~/.local/share/x11/xorg.conf.d
cat << 'EOF' > ~/.local/share/x11/xorg.conf.d/90-stylus-button.conf
Section "InputClass"
    Identifier "Surface Pen Button Remap"
    MatchProduct "Surface Pen"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "ButtonMapping" "1 3 2"
EndSection
EOF

echo ">> Stylus button remapping enabled (barrel button = eraser)."

# --- Step 9: Set default Surface kernel in systemd-boot ---
if [[ -d /boot/loader/entries ]]; then
    echo ">> Setting default boot entry to linux-surface..."
    sudo bootctl set-default "arch-*surface*"
fi

echo -e "\n✅ All setup complete. Please reboot to apply Surface kernel, touchscreen/pen settings, and HiDPI config."

