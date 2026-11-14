#!/usr/bin/env bash
# Runs inside the Kubuntu system being remixed (chroot). Ravana's files are already copied in.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C

# --- package sources: the live image points apt at its own CD; use the real archive while building
ls -la /etc/apt/sources.list.d/ /etc/apt/sources.list 2>&1 || true
mkdir -p /root/apt-keep
for f in /etc/apt/sources.list.d/cdrom.sources /etc/apt/sources.list; do
    [ -f "$f" ] && mv "$f" "/root/apt-keep/$(basename "$f")"
done
if ! ls /etc/apt/sources.list.d/*.sources >/dev/null 2>&1; then
cat > /etc/apt/sources.list.d/ubuntu.sources <<'SRC'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: resolute resolute-updates resolute-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: resolute-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
SRC
fi
for f in /etc/apt/sources.list.d/*.sources; do
    sed -i -E 's/^Components:.*/Components: main restricted universe multiverse/' "$f"
done
dpkg --add-architecture i386
apt-get update -qq

echo "steam steam/question select I AGREE" | debconf-set-selections
echo "steam steam/license note" | debconf-set-selections

optional() { for p in "$@"; do apt-get install -y -qq --no-install-recommends "$p" || echo "::warning::optional package $p not installed"; done; }

# --- what the macOS look needs
apt-get install -y -qq --no-install-recommends sassc gtk2-engines-murrine libglib2.0-dev-bin
apt-get install -y -qq --no-install-recommends qt6-style-kvantum fonts-inter os-prober git ca-certificates

# --- gaming
apt-get install -y -qq steam-installer
optional gamemode mangohud gamescope vulkan-tools mesa-vulkan-drivers:i386 libvulkan1:i386 libgl1:i386 \
         protontricks lutris winetricks

# --- identity: the name changes, the ID stays "ubuntu" so Ubuntu tools keep working
for OSR in /usr/lib/os-release; do
    sed -i -E 's/^NAME=.*/NAME="Ravana OS"/; s/^PRETTY_NAME=.*/PRETTY_NAME="Ravana OS (Ubuntu 26.04 base)"/' "$OSR"
    grep -q '^LOGO=' "$OSR" && sed -i 's/^LOGO=.*/LOGO=ravana-os/' "$OSR" || echo 'LOGO=ravana-os' >> "$OSR"
done

# --- macOS look on stock Plasma: WhiteSur (pinned commits), made the default for new users
get() { git clone -q "https://github.com/vinceliuice/$1.git" "/tmp/$1" && git -C "/tmp/$1" checkout -q "$2"; }
get WhiteSur-kde         cf4df59ce91004f7ea39358b1b8ff917d5c329f7
get WhiteSur-icon-theme  73d8040da51a9ed74e47c7366e7e9ff437601a5c
get WhiteSur-cursors     e190baf618ed95ee217d2fd45589bd309b37672b
get WhiteSur-gtk-theme   d5782652d412137e26fb8ff55b55a5572e4c6995
(cd /tmp/WhiteSur-kde && bash ./install.sh) || echo "::warning::WhiteSur-kde install failed"
(cd /tmp/WhiteSur-icon-theme && bash ./install.sh -d /usr/share/icons) || echo "::warning::WhiteSur icons failed"
(cd /tmp/WhiteSur-cursors && bash ./install.sh) || echo "::warning::WhiteSur cursors failed"
(cd /tmp/WhiteSur-gtk-theme && bash ./install.sh -d /usr/share/themes -c Dark -c Light) || echo "::warning::WhiteSur GTK theme failed"
ls /usr/share/plasma/look-and-feel /usr/share/icons /usr/share/Kvantum /usr/share/aurorae/themes 2>&1 | head -40

# Ravana's own global theme = WhiteSur dark + our layout (menu bar on top, floating dock below)
LNF=/usr/share/plasma/look-and-feel
if [ -d "$LNF/com.github.vinceliuice.WhiteSur-dark" ]; then
    cp -a "$LNF/com.github.vinceliuice.WhiteSur-dark" "$LNF/org.ravana.macos"
    python3 - <<'PY'
import json
p="/usr/share/plasma/look-and-feel/org.ravana.macos/metadata.json"
d=json.load(open(p)); d["KPlugin"]["Id"]="org.ravana.macos"; d["KPlugin"]["Name"]="Ravana (macOS style)"
json.dump(d,open(p,"w"),indent=2)
PY
    mkdir -p "$LNF/org.ravana.macos/contents/layouts"
    cat > "$LNF/org.ravana.macos/contents/layouts/org.kde.plasma.desktop-layout.js" <<'JS'
// Ravana OS: macOS-style layout from stock Plasma parts (no custom widgets, nothing to break)
var ds = desktops();
for (var i = 0; i < ds.length; i++) {
    ds[i].wallpaperPlugin = "org.kde.image";
    ds[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    ds[i].writeConfig("Image", "file:///usr/share/wallpapers/Ravana/");
}
// menu bar
var bar = new Panel;
bar.location = "top";
bar.height = 28;
bar.hiding = "none";
bar.addWidget("org.kde.plasma.kickoff");
bar.addWidget("org.kde.plasma.appmenu");
bar.addWidget("org.kde.plasma.panelspacer");
bar.addWidget("org.kde.plasma.systemtray");
bar.addWidget("org.kde.plasma.digitalclock");
// dock
var dock = new Panel;
dock.location = "bottom";
dock.height = 60;
dock.alignment = "center";
dock.lengthMode = "fit";
dock.floating = true;
dock.hiding = "dodgewindows";
dock.addWidget("org.kde.plasma.icontasks");
JS
else
    echo "::warning::WhiteSur look-and-feel missing: layout not installed"
fi
kwriteconfig6 --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage org.ravana.macos
# macOS window buttons on the left
kwriteconfig6 --file /etc/xdg/kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft XIA
kwriteconfig6 --file /etc/xdg/kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
# the login screen uses Ravana's theme when present
mkdir -p /etc/sddm.conf.d
if [ -f /usr/share/sddm/themes/ravana/Main.qml ]; then
    printf '[Theme]\nCurrent=ravana\nCursorTheme=WhiteSur-cursors\nFont=Inter,10\n' > /etc/sddm.conf.d/10-ravana.conf
fi

# --- installing next to another Linux
# Own boot-loader folder on the shared EFI partition (Kubuntu's default "ubuntu" would collide with
# an existing Ubuntu's), and GRUB lists the other systems it finds.
sed -i 's/^efiBootloaderId:.*/efiBootloaderId: "ravana"/' /etc/calamares/modules/bootloader.conf
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/90-ravana.cfg <<'GRUBD'
GRUB_DISABLE_OS_PROBER=false
GRUB_DISTRIBUTOR="Ravana OS"
GRUBD

# --- tidy
[ -f /root/apt-keep/cdrom.sources ] && mv /root/apt-keep/cdrom.sources /etc/apt/sources.list.d/cdrom.sources
[ -f /root/apt-keep/sources.list ] && mv /root/apt-keep/sources.list /etc/apt/sources.list
rm -rf /root/apt-keep
apt-get clean
rm -f /quickshell-runtime-packages.txt
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
