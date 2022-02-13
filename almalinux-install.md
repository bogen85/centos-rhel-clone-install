Preperation
Boot system resucecd

Disable firewall, set root password
```sh
systemctl disable iptables
systemctl stop iptables
systemctl restart sshd
systemctl status sshd
ip addr
passwd
```

Optional: Log in as root from another system

Check partiton table
```sh
sgdisk --print /dev/nvme0n1
```

Prepare as follows:
```txt
...
Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048         2099199   1024.0 MiB  EF00  EFI-boot
   2         2099200       270534655   128.0 GiB   8304  root/
   3       270534656       538970111   128.0 GiB   8200  swap
   4       538970112      3907029134   1.6 TiB     8312  /home
```

Clear signatures (if this is a reinstall)
```sh
dd if=/dev/zero of=/dev/nvme0n1p1 bs=65536 count=1
dd if=/dev/zero of=/dev/nvme0n1p2 bs=65536 count=1
dd if=/dev/zero of=/dev/nvme0n1p3 bs=65536 count=1
dd if=/dev/zero of=/dev/nvme0n1p4 bs=65536 count=1
blkid /dev/nvme0n1*
```

Make filesystems
```sh
mkfs.vfat -F32 -n EFI-BOOT /dev/nvme0n1p1
mkfs.ext4 -L linux-root /dev/nvme0n1p2
mkswap -L linux-swap /dev/nvme0n1p3
mkfs.xfs -L linux-home /dev/nvme0n1p4
blkid /dev/nvme0n1*
```


Mount and check fstab
```sh
mount /dev/nvme0n1p2 /mnt
swapon /dev/nvme0n1p3
mkdir -pv /mnt/{boot,home}
mount /dev/nvme0n1p1 /mnt/boot
mount /dev/nvme0n1p4 /mnt/home
genfstab -U /mnt # note root UUID for future /etc/kernel/cmdline
```

Get image and check SHA-256
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


extract image and create systemd machine id
```sh
pv rootfs.tar.xz | tar Jpxf - --directory=/mnt/
systemd-machine-id-setup --root=/mnt
```

Enter chroot and install initial packages
```sh
arch-chroot /mnt

dnf upgrade --refresh -y
dnf erase subscription-manager -y
dnf install -y epel-release
dnf upgrade --refresh -y

dnf install -y htop mlocate openssh-server micro util-linux-user less which man-db bash-completion git
exit # to get bash completion on reentry
```

Enable elrepo, install kernel and more packages
```sh
arch-chroot /mnt

sudo rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
sudo dnf install https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm -y

micro /etc/yum.repos.d/elrepo.repo
# enable [elrepo-kernel]
# enable [elrepo-extras]

dnf upgrade --refresh -y

dnf install -y kernel-lt efibootmgr systemd-container pciutils wget tar lshw
```

Set up bootloader
```sh
micro /etc/kernel/cmdline
# note root UUID from previous: genfstab -U /mnt
# cmdline appropitately: root=UUID=4d18d6d4-86fc-41f1-b6b3-a302d04cf0e7 rw quiet

bootctl install

ls /lib/modules/ # note kernel version, use for: export kver=
export kver=5.4.179-1.el8.elrepo.x86_64
kernel-install add $kver  /lib/modules/$kver/vmlinuz
dnf reinstall -y kernel-lt-core

bootctl
```

Prepare for soft boot
```sh
systemctl disable sshd
passwd
exit
```

Soft boot into new install
```sh
systemd-nspawn --network-macvlan=eno1 --boot --directory=/mnt
dhclient mv-eno1
updatedb
```

Create admin account
```sh
useradd -r -m admin
passwd admin
chsh admin
gpasswd -a admin wheel
```

Remove and disable grub
```sh
dnf remove -y grub2-common grub2-tools-minimal grubby grub2-tools

micro /etc/yum.conf
# add: exclude=*grub2* grubby ipxe-* java-* *-java* *jdk* javapackages-*
```

Install useful grub deps, more packages, set hostname
```sh
dnf install -y file which dosfstools

micro /etc/hostname # add host name

hostname -F /etc/hostname
systemctl enable sshd
halt # poweroff container
```


Prepare for hard boot
```sh
genfstab -U /mnt > /mnt/etc/fstab
arch-chroot /mnt
cat /etc/fstab
dnf install NetworkManager
systemctl enable NetworkManager
exit
```

Prepare to reboot
```sh
umount -R /mnt/
# umount /mnt/home
# umount /mnt/boot
# umount /mnt/
```

Reboot into fresh system

Prepare Desktop environment
```sh
# login as admin
sudo dnf groupinstall Xfce
sudo dnf install xorg-x11-drv-intel xorg-x11-drv-evdev
sudo systemctl enable gdm
sudo systemctl start gdm
sudo systemctl status gdm
```
