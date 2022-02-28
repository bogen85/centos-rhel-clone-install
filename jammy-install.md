## Preperation
- Dowload latest ubuntu server installer
- http://www.releases.ubuntu.com/21.10/ubuntu-21.10-live-server-amd64.iso
- Write image to thumbdrive (change /dev/sdb if need be)
- sudo qemu-img convert -p -t directsync -f raw -O raw ubuntu-21.10-live-server-amd64.iso /dev/sdb

## Exit installer
Press Alt-F3

## Check ssh, set user password
```sh
systemctl status ssh
ip addr # 192.168.10.192
passwd
```

## Log in as ubuntu-server from another system, prep installer
- ssh ubuntu-server@192.168.10.192

```sh
sudo apt -y update
sudo apt -y install pv apt-file systemd-container arch-install-scripts micro
sudo apt-file update
```

## Check partiton table
```sh
sudo sgdisk --print /dev/nvme0n1
# change /dev/nvme0n1 as needed (such as /dev/sda)
# example:
sudo sgdisk --print /dev/sda
```

### Prepare as follows (leave off /home if not development/user machine):
```txt
...
Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048         2099199   1024.0 MiB  EF00  EFI-boot
   2         2099200       270534655   128.0 GiB   8304  root/
   3       270534656       538970111   128.0 GiB   8200  swap
   4       538970112      3907029134   1.6 TiB     8312  /home
```

### alternative
```txt
Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048         2099199   1024.0 MiB  EF00  EFI-boot
   2         2099200        35653631   16.0 GiB    8200  swap
   3        35653632       250069646   102.2 GiB   8304  root/
```

### Clear signatures (if this is a reinstall)
```sh
sudo dd if=/dev/zero of=/dev/nvme0n1p1 bs=4096 count=1
sudo dd if=/dev/zero of=/dev/nvme0n1p2 bs=4096 count=1
sudo dd if=/dev/zero of=/dev/nvme0n1p3 bs=4096 count=1
sudo dd if=/dev/zero of=/dev/nvme0n1p4 bs=4096 count=1
sudo blkid /dev/nvme0n1*
```

### Clear signatures (if this is a reinstall) -- alternative
```sh
sudo dd if=/dev/zero of=/dev/sda1 bs=4096 count=1
sudo dd if=/dev/zero of=/dev/sda2 bs=4096 count=1
sudo dd if=/dev/zero of=/dev/sda3 bs=4096 count=1
sudo blkid /dev/sda*
```

### Make filesystems
```sh
sudo mkfs.vfat -F32 -n EFI-BOOT /dev/nvme0n1p1
sudo mkfs.ext4 -L linux-root /dev/nvme0n1p2
sudo mkswap -L linux-swap /dev/nvme0n1p3
sudo mkfs.xfs -L linux-home /dev/nvme0n1p4
sudo blkid /dev/nvme0n1*
```

### Make filesystems -- alternative
```sh
sudo mkfs.vfat -F32 -n EFI-BOOT /dev/sda1
sudo mkswap -L linux-swap /dev/sda2
sudo mkfs.ext4 -L linux-root /dev/sda3
sudo blkid /dev/sda*
```

### Mount and check fstab
```sh
sudo mount /dev/nvme0n1p2 /mnt
sudo swapon /dev/nvme0n1p3
sudo mkdir -pv /mnt/boot/efi /mnt/home
sudo mount /dev/nvme0n1p1 /mnt/boot/efi
sudo mount /dev/nvme0n1p4 /mnt/home
sudo genfstab -U /mnt # note root UUID for future /etc/kernel/cmdline
```

### Mount and check fstab -- alternative
```sh
sudo mount /dev/sda3 /mnt
sudo swapon /dev/sda2
sudo mkdir -pv /mnt/boot
sudo mount /dev/sda1 /mnt/boot
sudo genfstab -U /mnt # note root UUID for future /etc/kernel/cmdline
```

### Get image and check SHA-256
```sh
# check https://us.lxd.images.canonical.com/images/ubuntu/jammy/amd64/default/ and set jammy to latest
export jammy=20220227_07:43

export jammy_base_url=https://us.lxd.images.canonical.com/images/ubuntu/jammy/amd64/default
export jammy_url=${jammy_base_url}/${jammy}

wget ${jammy_url}/SHA256SUMS
wget ${jammy_url}/rootfs.tar.xz

fgrep rootfs.tar.xz SHA256SUMS > SHA256SUMS.rootfs
sha256sum -c SHA256SUMS.rootfs
```

### extract image and create systemd machine id
```sh
pv rootfs.tar.xz | sudo tar Jpxf - --directory=/mnt/
sudo systemd-machine-id-setup --root=/mnt
alias chroot-mnt='sudo arch-chroot /mnt'
sudo genfstab -U /mnt | sudo dd of=/mnt/etc/kernel/cmdline
```

### Install initial packages
```sh
echo 'APT::Install-Recommends "0";' | sudo tee    /mnt/etc/apt/apt.conf.d/99apt.conf
echo 'APT::Install-Suggests "0";' 	| sudo tee -a /mnt/etc/apt/apt.conf.d/99apt.conf

chroot-mnt apt -y update
chroot-mnt apt -y full-upgrade

deny_pkgs="os-prober libimobiledevice6 grub-pc grub-pc-bin grub2-common"
deny_pkgs+=" grub-common grub-efi-amd64 grub-efi-ia32 lilo"

for pkg in $deny_pkgs; do chroot-mnt apt-mark hold $pkg; done

chroot-mnt apt install -y \
	htop mlocate openssh-server micro man-db bash-completion git aptitude \
	efibootmgr systemd-container pciutils wget lshw apt-file rsync fontconfig

chroot-mnt apt-file update
```

### Set up boot command line
```sh
sudo micro /mnt/etc/kernel/cmdline
# set cmdline appropitately: root=UUID=4d18d6d4-86fc-41f1-b6b3-a302d04cf0e7 rw quiet systemd.show_status=yes
```

### Patch and verify boot command line
```sh
sudo sed 's,UUID=,/dev/disk/by-uuid/,' -i /mnt/etc/kernel/cmdline
chroot-mnt cat /etc/kernel/cmdline
```

### Set up efi boot updater
```sh
sudo dd of=/mnt/etc/kernel/postinst.d/zz-update-boot-efi # paste in zz-update-boot-efi.sh content
# Ctrl-D when done
```

### Set up bootloader and install kernel
```sh
chroot-mnt chmod -v 755 /etc/kernel/postinst.d/zz-update-boot-efi
chroot-mnt mkdir -pv /etc/initramfs-tools/post-update.d/ /etc/kernel/postrm.d/ /etc/initramfs/post-update.d/
chroot-mnt ln -sv /etc/kernel/postinst.d/zz-update-boot-efi /etc/initramfs-tools/post-update.d/
chroot-mnt ln -sv /etc/kernel/postinst.d/zz-update-boot-efi /etc/kernel/postrm.d/
chroot-mnt ln -sv /etc/kernel/postinst.d/zz-update-boot-efi /etc/initramfs/post-update.d/

chroot-mnt bootctl install --make-machine-id-directory=no

chroot-mnt apt install -y --install-recommends linux-image-generic

chroot-mnt bootctl
chroot-mnt efibootmgr -v
chroot-mnt bash -c 'sha256sum $(find /boot -type f | sort)'
```

### Prepare for soft boot
```sh
chroot-mnt systemctl disable ssh
chroot-mnt passwd
chroot-mnt useradd -r -m admin
chroot-mnt passwd admin
chroot-mnt chsh admin --shell /bin/bash
chroot-mnt gpasswd -a admin sudo
chroot-mnt updatedb
```

### Set hostname
```sh
chroot-mnt bash -c 'echo NEW-HOSTNAME > /etc/hostname' # change NEW-HOSTNAME appropiately
```

### set network device
```sh
ip addr # change eno1 accordingly in following lines to nic with lan/wan address
netdev=eno1
```

### Soft boot into new install
```sh
sudo sed s,eth0,mv-$netdev,g -i /mnt/etc/netplan/10-lxc.yaml
sudo cat /mnt/etc/netplan/10-lxc.yaml
sudo systemd-nspawn --network-macvlan=$netdev --boot --directory=/mnt
# login as admin
```

### verify hostname and dhcp success in container
```sh
ip addr # verify ip addr
exit
```

### login as root halt container
```sh
halt	# halt container
```

### fix nic name for netplan
```sh
sudo sed s,mv-$netdev,$netdev,g -i /mnt/etc/netplan/10-lxc.yaml
sudo cat /mnt/etc/netplan/10-lxc.yaml
```

### Prepare for hard boot
```sh
chroot-mnt systemctl enable ssh
sudo genfstab -U /mnt | sed 's,UUID=,/dev/disk/by-uuid/,' | sudo dd of=/mnt/etc/fstab
chroot-mnt cat /etc/fstab
chroot-mnt ln -svf /usr/share/zoneinfo/CST6CDT /etc/localtime
```

### Replace /etc/default/console-setup with following content (See dd line in next section)
```sh
# CONFIGURATION FILE FOR SETUPCON

# Consult the console-setup(5) manual page.

ACTIVE_CONSOLES="/dev/tty[1-6]"

CHARMAP="UTF-8"

CODESET="guess"
FONTFACE="Terminus"
FONTSIZE="16x32"

VIDEOMODE=

# The following is an example how to use a braille font
# FONT='lat9w-08.psf.gz brl-8x8.psf'
```

### Setup console font (step #1)
```sh
sudo dd of=/etc/default/console-setup # see above for content to paste
# Ctrl-D when done
```

### Setup console font (step #2)
```sh
chroot-mnt dpkg-reconfigure console-setup -u # Answer per what was put in /etc/default/console-setup
```

### Prepare to reboot
```sh
sudo umount -R /mnt/
```

### Reboot into fresh system
