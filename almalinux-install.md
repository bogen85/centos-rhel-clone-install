## Preperation
- Dowload latest ubuntu server installer
- http://www.releases.ubuntu.com/21.10/ubuntu-21.10-live-server-amd64.iso
- Write image to thumbdrive (change /dev/sdb if need be)
- sudo qemu-img convert -p -t directsync -f raw -O raw ubuntu-21.10-live-server-amd64.iso /dev/sdb

## Exit installer
Press Alt-F3

## Check ssh, set user password
```sh
setfont Uni2-Terminus32x16.psf.gz # optional, set console font
systemctl status ssh
ip addr # 192.168.10.192
passwd
```

## Log in as ubuntu-server from another system, prep installer
- ssh ubuntu-server@192.168.10.192

```sh
sudo apt -y update
sudo apt -y install pv apt-file systemd-container arch-install-scripts
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
sudo mkdir -pv /mnt/{boot,home}
sudo mount /dev/nvme0n1p1 /mnt/boot
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
# check https://us.lxd.images.canonical.com/images/almalinux/8/amd64/default/ and set almalinux to latest
export almalinux=20220212_23:08

export almalinux_base_url=https://us.lxd.images.canonical.com/images/almalinux/8/amd64/default
export almalinux_url=${almalinux_base_url}/${almalinux}

wget ${almalinux_url}/SHA256SUMS
wget ${almalinux_url}/rootfs.tar.xz

fgrep rootfs.tar.xz SHA256SUMS > SHA256SUMS.rootfs
sha256sum -c SHA256SUMS.rootfs
```


### extract image and create systemd machine id
```sh
sudo -v
pv rootfs.tar.xz | sudo tar Jpxf - --directory=/mnt/
sudo systemd-machine-id-setup --root=/mnt
```

### Enter chroot and install initial packages
```sh
sudo arch-chroot /mnt
#####################

dnf upgrade --refresh -y
dnf erase subscription-manager -y
dnf install -y epel-release
dnf upgrade --refresh -y

dnf install -y htop mlocate openssh-server micro util-linux-user less which man-db bash-completion git
exit # to get bash completion on reentry
```

### Enable elrepo, install more packages
```sh
sudo arch-chroot /mnt
#####################
dnf install -y elrepo-release

micro /etc/yum.repos.d/elrepo.repo
# enable [elrepo-kernel]
# enable [elrepo-extras]

dnf upgrade --refresh -y

dnf install -y efibootmgr systemd-container pciutils wget tar lshw
exit
```

```sh
sudo genfstab -U /mnt
```

### Set up bootloader and install kernel
```sh
sudo arch-chroot /mnt
#####################

micro /etc/kernel/cmdline
# note root UUID from previous: genfstab -U /mnt
# cmdline appropitately: root=UUID=4d18d6d4-86fc-41f1-b6b3-a302d04cf0e7 rw quiet
sed 's,UUID=,/dev/disk/by-uuid/,' -i /etc/kernel/cmdline
cat /etc/kernel/cmdline

bootctl install

# ls /lib/modules/ # note kernel version, use for: export kver=
# export kver=5.4.179-1.el8.elrepo.x86_64
# kernel-install add $kver  /lib/modules/$kver/vmlinuz
dnf install -y kernel-ml

bootctl
efibootmgr -v
find /boot
```

### Prepare for soft boot
```sh
systemctl disable sshd
passwd
exit
```

### Soft boot into new install
```sh
ip addr # change enp1s0 accordingly in following lines to nic with lan/wan address
netdev=enp1s0
sudo systemd-nspawn --network-macvlan=$netdev --boot --directory=/mnt
#####################################################################
netdev=enp1s0
dhclient mv-$netdev
ip addr
updatedb
```

### Create admin account
```sh
useradd -r -m admin
passwd admin
chsh admin --shell /bin/bash
gpasswd -a admin wheel
```

### Remove and disable grub (and other undesirables)
```sh
dnf remove -y grub2-common grub2-tools-minimal grubby grub2-tools

echo 'exclude=*grub2* grubby java-* *-java* *jdk* javapackages-*' >> /etc/yum.conf
micro /etc/yum.conf

dnf reinstall -y kernel-ml-core
```

### Install useful grub deps, more packages, set hostname
```sh
dnf install -y file which dosfstools

echo NEW-HOSTNAME > /etc/hostname # change NEW-HOSTNAME appropiately

hostname -F /etc/hostname
hostname
systemctl enable sshd
halt # poweroff container
```


### Prepare for hard boot
```sh
sudo genfstab -U /mnt | sed 's,UUID=,/dev/disk/by-uuid/,' | sudo tee /mnt/etc/fstab
sudo arch-chroot /mnt
#####################
cat /etc/fstab

dnf install NetworkManager rsync keychain fontconfig terminus-fonts-console clang
systemctl enable NetworkManager
ln -svf /usr/share/zoneinfo/CST6CDT /etc/localtime
echo >> /etc/vconsole.conf 'FONT=ter-u32n'
exit
```

### Prepare to reboot
```sh
sudo umount -R /mnt/
```

### Reboot into fresh system
