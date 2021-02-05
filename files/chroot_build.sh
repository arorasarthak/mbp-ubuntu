#!/bin/bash

set -eu -o pipefail

echo >&2 "===]> Info: Configure environment... "

mount none -t proc /proc
mount none -t sysfs /sys
mount none -t devpts /dev/pts

export HOME=/root
export LC_ALL=C

echo "ubuntu-fs-live" >/etc/hostname

echo >&2 "===]> Info: Configure and update apt... "

cat <<EOF >/etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu/ focal main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ focal-security main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ focal-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ focal-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ focal-updates main restricted universe multiverse
EOF
apt-get update

echo >&2 "===]> Info: Install systemd and Ubuntu MBP Repo... "

apt-get install -y systemd-sysv gnupg curl wget

mkdir -p /etc/apt/sources.list.d
apt-get update

echo >&2 "===]> Info: Configure machine-id and divert... "

dbus-uuidgen >/etc/machine-id
ln -fs /etc/machine-id /var/lib/dbus/machine-id
dpkg-divert --local --rename --add /sbin/initctl
ln -s /bin/true /sbin/initctl

echo >&2 "===]> Info: Install packages needed for Live System... "

cd /tmp/setup_files && dpkg -i *.deb && cd -

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  ubuntu-standard \
  sudo \
  casper \
  lupin-casper \
  discover \
  laptop-detect \
  os-prober \
  network-manager \
  resolvconf \
  net-tools \
  wireless-tools \
  wpagui \
  locales \
  initramfs-tools \
  binutils \
  linux-generic \
  linux-headers-generic \
  grub-efi-amd64-signed \
  intel-microcode \
  thermald

echo >&2 "===]> Info: Install window manager... "

apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  plymouth-theme-ubuntu-logo \
  ubuntu-desktop-minimal \
  ubuntu-gnome-wallpapers \
  snapd

echo >&2 "===]> Info: Install Graphical installer... "

apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  ubiquity \
  ubiquity-casper \
  ubiquity-frontend-gtk \
  ubiquity-slideshow-ubuntu \
  ubiquity-ubuntu-artwork

echo >&2 "===]> Info: Install useful applications... "

apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  git \
  curl \
  nano \
  neovim \
  make \
  gcc \
  dkms \
  iwd

echo >&2 "===]> Info: Change initramfs format (for grub)... "
sed -i "s/COMPRESS=lz4/COMPRESS=gzip/g" "/etc/initramfs-tools/initramfs.conf"

echo >&2 "===]> Info: Add drivers... "

BCE_DRIVER_GIT_URL=https://github.com/MCMrARM/mbp2018-bridge-drv.git
BCE_DRIVER_BRANCH_NAME=master
BCE_DRIVER_COMMIT_HASH=b43fcc069da73e051072fde24af4014c9c487286
APPLE_IB_DRIVER_GIT_URL=https://github.com/marcosfad/macbook12-spi-driver.git
APPLE_IB_DRIVER_BRANCH_NAME=mbp15

apt-get install -y grub-efi-amd64-signed git build-essential

mkdir -p /lib/modules/"${KERNEL_VERSION}"/extra

### Install custom drivers
## BCE - Apple T2
echo >&2 "===]> Info: Downloading BCE driver... ";
git clone --depth 1 --single-branch --branch "${BCE_DRIVER_BRANCH_NAME}" "${BCE_DRIVER_GIT_URL}" ./bce
cd bce || exit
git checkout "${BCE_DRIVER_COMMIT_HASH}"

make -C /lib/modules/"${KERNEL_VERSION}"/build/ M="$(pwd)" modules
cp -rv ./bce.ko /lib/modules/"${KERNEL_VERSION}"/extra
cd ..

## Touchbar
echo >&2 "===]> Info: Downloading Touchbar driver... ";
git clone --single-branch --branch ${APPLE_IB_DRIVER_BRANCH_NAME} ${APPLE_IB_DRIVER_GIT_URL} ./touchbar
cd touchbar || exit

make -C /lib/modules/"${KERNEL_VERSION}"/build/ M="$(pwd)" modules
cp -rv ./*.ko /lib/modules/"${KERNEL_VERSION}"/extra

### Add custom drivers to be loaded at boot
echo >&2 "===]> Info: Setting up GRUB to load custom drivers at boot... ";
echo -e 'hid-apple\nbcm5974\nsnd-seq\nbce\napple_ibridge\napple_ib_tb' > /etc/modules-load.d/bce.conf
echo -e 'blacklist thunderbolt' > /etc/modprobe.d/blacklist.conf

rm -rfv /touchbar
rm -rfv /bce

echo >&2 "===]> Info: Update initramfs... "

## Add custom drivers to be loaded at boot
/usr/sbin/depmod -a "${KERNEL_VERSION}"
update-initramfs -u -v -k "${KERNEL_VERSION}"

echo >&2 "===]> Info: Remove unused applications ... "

apt-get purge -y -qq \
  transmission-gtk \
  transmission-common \
  gnome-mahjongg \
  gnome-mines \
  gnome-sudoku \
  aisleriot \
  hitori \
  xiterm+thai \
  make \
  gcc \
  vim \
  binutils \
  linux-generic \
  linux-headers-5.4.0-59 \
  linux-headers-5.4.0-59-generic \
  linux-headers-generic \
  linux-image-5.4.0-59-generic \
  linux-image-generic \
  linux-modules-5.4.0-59-generic \
  linux-modules-extra-5.4.0-59-generic \
  linux-headers-5.4.0-65 \
  linux-headers-5.4.0-65-generic \
  linux-image-5.4.0-65-generic \
  linux-modules-5.4.0-65-generic \
  linux-modules-extra-5.4.0-65-generic

apt-get autoremove -y

echo >&2 "===]> Info: Reconfigure environment ... "

locale-gen --purge en_US.UTF-8 en_US
printf 'LANG="C.UTF-8"\nLANGUAGE="C.UTF-8"\n' >/etc/default/locale

dpkg-reconfigure -f readline resolvconf

cat <<EOF >/etc/NetworkManager/NetworkManager.conf
[main]
rc-manager=resolvconf
plugins=ifupdown,keyfile
dns=dnsmasq
[ifupdown]
managed=false
EOF
dpkg-reconfigure network-manager

echo >&2 "===]> Info: Configure Network Manager to use iwd... "
mkdir -p /etc/NetworkManager/conf.d
printf '[device]\nwifi.backend=iwd\n' > /etc/NetworkManager/conf.d/wifi_backend.conf
#systemctl enable iwd.service

echo >&2 "===]> Info: Cleanup the chroot environment... "

truncate -s 0 /etc/machine-id
rm /sbin/initctl
dpkg-divert --rename --remove /sbin/initctl
apt-get clean
rm -rf /tmp/* ~/.bash_history
rm -rf /tmp/setup_files

umount -lf /dev/pts
umount -lf /sys
umount -lf /proc

export HISTSIZE=0
