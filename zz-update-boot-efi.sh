#!/bin/bash
# /etc/kernel/postinst.d/zz-update-boot-efi.sh
# CudaText: file_type="Bash script"; tab_size=2; tab_spaces=yes;

set -euo pipefail

etc_kernel_cmdline=/etc/kernel/cmdline
cmdline=$(echo $(cat $etc_kernel_cmdline))

efi=/boot/efi

current=${efi}/linux/current
previous=${efi}/linux/previous
entries=${efi}/loader/entries

etc_loader_conf=/etc/boot/efi/loader/loader.conf

loader_conf=${efi}/loader/loader.conf
loader_conf_content='default current.conf
timeout 4
console-mode 0
editor yes
'

copy () {
  cp -v --dereference --remove-destination $1 $2
}

make_loader () {
  conf=$loader_conf
  echo '--------'

  if [ -f $etc_loader_conf ]; then
    copy $etc_loader_conf $conf
  else
    rm -vf $conf
    echo Creating $conf
    printf > $conf '%s' "${loader_conf_content}"
  fi
  cat $conf
}

make_conf () {
  entry=$1
  conf=${entries}/$entry.conf
  echo '--------'
  rm -vf $conf
  echo "Creating $conf (using $etc_kernel_cmdline for options)"
  printf >> $conf 'title   %s kernel\n' $entry
  printf >> $conf 'linux   /linux/%s/vmlinuz\n' $entry
  printf >> $conf 'initrd  /linux/%s/initrd\n' $entry
  printf >> $conf 'options %s\n' "${cmdline}"
  cat $conf
}

check_file () {
  [ -f $1 ] && return
  printf 'Fail: %s does not exist!\n' $1
  false
}

main () {
  echo '--------'
  check_file "${etc_kernel_cmdline}"

  mkdir -pv $current $previous $entries
  echo 'updating efi boot loader'
  echo
  copy /boot/vmlinuz ${current}/vmlinuz
  copy /boot/initrd.img ${current}/initrd
  echo
  copy /boot/vmlinuz.old ${previous}/vmlinuz
  copy /boot/initrd.img.old ${previous}/initrd

  make_conf current
  make_conf previous
  make_loader
}

main
