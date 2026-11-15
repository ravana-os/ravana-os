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

# --- updates that can always be undone
# Installs use btrfs with Ubuntu's @ / @home layout (what Timeshift needs). Before apt changes
# anything, a Timeshift snapshot is taken; GRUB lists the snapshots ("Ravana OS snapshots") so a
# bad update is undone by picking the one from before it, even when the desktop no longer starts.
apt-get install -y -qq --no-install-recommends timeshift btrfs-progs inotify-tools make gawk
sed -i -E 's/^defaultFileSystemType:.*/defaultFileSystemType: "btrfs"/' /etc/calamares/modules/partition.conf
grep -n -A12 -i 'btrfsSubvolumes' /etc/calamares/modules/mount.conf || echo "mount.conf has no btrfs subvolume list"
python3 - <<'PY'
# Ubuntu's layout: @ for the system, @home for people's files (Timeshift restores @ only)
import re
p = "/etc/calamares/modules/mount.conf"
s = open(p).read()
s = re.sub(r"\nbtrfsSubvolumes:.*?(?=\n\S|\Z)", "", s, flags=re.S)
s = s.rstrip("\n") + """
btrfsSubvolumes:
    - mountPoint: /
      subvolume: /@
    - mountPoint: /home
      subvolume: /@home
"""
open(p, "w").write(s)
PY
grep -n -A6 'btrfsSubvolumes' /etc/calamares/modules/mount.conf

# grub-btrfs (pinned release): adds the snapshots to the GRUB menu and keeps it current
git clone -q --depth 1 --branch v4.14 https://github.com/Antynea/grub-btrfs.git /tmp/grub-btrfs
test "$(git -C /tmp/grub-btrfs rev-parse HEAD)" = 2fcfbe967637166b88dadd49c834807243a941bf || \
    test "$(git -C /tmp/grub-btrfs rev-parse 'HEAD^{}')" = 2fcfbe967637166b88dadd49c834807243a941bf || \
    echo "::warning::grub-btrfs v4.14 is not the reviewed commit"
make -C /tmp/grub-btrfs install SYSTEMD=true INITCPIO=false >/dev/null
sed -i 's|^#\?GRUB_BTRFS_SUBMENUNAME=.*|GRUB_BTRFS_SUBMENUNAME="Ravana OS snapshots"|' /etc/default/grub-btrfs/config
mkdir -p /etc/systemd/system/grub-btrfsd.service.d
cat > /etc/systemd/system/grub-btrfsd.service.d/10-timeshift.conf <<'UNIT'
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto
UNIT
systemctl enable grub-btrfsd.service

# snapshot before every apt change (at most one per 10 minutes; skipped quietly when the root
# is not btrfs, e.g. the live USB)
cat > /usr/libexec/ravana-snapshot <<'SNAP'
#!/bin/sh
[ "$(findmnt -n -o FSTYPE /)" = btrfs ] || exit 0
command -v timeshift >/dev/null || exit 0
stamp=/run/ravana-snapshot.stamp
if [ -f "$stamp" ] && [ $(( $(date +%s) - $(stat -c %Y "$stamp") )) -lt 600 ]; then exit 0; fi
touch "$stamp"
timeout 300 timeshift --create --scripted --tags O --comments "before update $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1 || true
exit 0
SNAP
chmod 0755 /usr/libexec/ravana-snapshot
echo 'DPkg::Pre-Invoke { "/usr/libexec/ravana-snapshot"; };' > /etc/apt/apt.conf.d/80ravana-snapshot
# Timeshift settings for new installs: btrfs mode, keep 5 update snapshots, 3 daily, 2 weekly
mkdir -p /etc/timeshift
cat > /etc/timeshift/default.json <<'TS'
{
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "0",
  "count_weekly" : "2",
  "count_daily" : "3",
  "count_hourly" : "0",
  "count_boot" : "0",
  "count_ondemand" : "5"
}
TS

# Ubuntu's own updates: security fixes install by themselves, everything else waits for the user;
# never jump to a new Ubuntu release by itself (stays on the 26.04 LTS line)
apt-get install -y -qq --no-install-recommends unattended-upgrades
sed -i -E 's/^Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades 2>/dev/null || true

# (what shows the "Try / Install" welcome screen: printed so it can be rebranded)
grep -l -i -E 'welcome|installer|calamares' /etc/xdg/autostart/*.desktop /usr/share/applications/*.desktop 2>/dev/null | while read -r f; do
    echo "== $f ($(dpkg -S "$f" 2>/dev/null | cut -d: -f1))"; grep -E '^(Exec|Name)=' "$f"; done || true

# --- tidy
[ -f /root/apt-keep/cdrom.sources ] && mv /root/apt-keep/cdrom.sources /etc/apt/sources.list.d/cdrom.sources
[ -f /root/apt-keep/sources.list ] && mv /root/apt-keep/sources.list /etc/apt/sources.list
rm -rf /root/apt-keep
apt-get clean
rm -f /quickshell-runtime-packages.txt
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
