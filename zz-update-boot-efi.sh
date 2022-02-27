#!/bin/bash
# /etc/kernel/postinst.d/zz-update-boot-efi
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

dv=""

copy () {
  cp $dv --dereference --remove-destination $1 $2
}

vmsg () {
  [ -z "$dv" ] && return
  echo $@
}

make_loader () {
  conf=$loader_conf
  vmsg '--------'

  if [ -f $etc_loader_conf ]; then
    copy $etc_loader_conf $conf
  else
    rm $dv -f $conf
    vmsg Creating $conf
    printf > $conf '%s' "${loader_conf_content}"
  fi
  vmsg $(cat $conf)
}

make_conf () {
  entry=$1
  conf=${entries}/$entry.conf
  vmsg '--------'
  rm $dv -f $conf
  vmsg "Creating $conf (using $etc_kernel_cmdline for options)"
  printf >> $conf 'title   %s kernel\n' $entry
  printf >> $conf 'linux   /linux/%s/vmlinuz\n' $entry
  printf >> $conf 'initrd  /linux/%s/initrd\n' $entry
  printf >> $conf 'options %s\n' "${cmdline}"
  vmsg $(cat $conf)
}

need_files () {
  for i in $@; do
    [ -f $i ] && continue
    printf 'Fail: %s does not exist!\n' $1
    false
  done
}

check_files () {
  for i in $@; do
    [ -f $i ] && continue
    printf 'Too early: %s does not exist!\n' $1
    exit 0
  done
}

main () {
  [ $# != 0 ] && [ "$1" == "--verbose" ] && dv="-v"
  vmsg '--------'
  echo 'updating efi boot loader'
  need_files "${etc_kernel_cmdline}"
  check_files /boot/vmlinuz /boot/initrd.img /boot/vmlinuz.old /boot/initrd.img.old

  mkdir -p $dv $current $previous $entries
  vmsg
  copy /boot/vmlinuz ${current}/vmlinuz
  copy /boot/initrd.img ${current}/initrd
  vmsg
  copy /boot/vmlinuz.old ${previous}/vmlinuz
  copy /boot/initrd.img.old ${previous}/initrd

  make_conf current
  make_conf previous
  make_loader
}

main $@
