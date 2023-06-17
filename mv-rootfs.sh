#!/bin/bash
AUTHOR='neko <setq@milkv.io>'
VERSION='0.10'

SCRIPT_NAME=$(basename $0)
ROOT_MOUNT=$(mktemp -d)
DISTRO=`cat /etc/os-release | grep ^ID= | sed -e 's/ID\=//g'`

if [ $(id -u) != 0 ]; then
  echo -e "${SCRIPT_NAME} needs to be run as root.\n"
  exit 1
fi


confirm() {
  printf "%s [Y/n] " "$1"
  read resp < /dev/tty
  if [ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ]; then
    return 0
  fi
  if [ "$2" == "abort" ]; then
    echo -e "Abort.\n"
    exit 0
  fi
  return 1
}


rsync_rootfs() {
  rsync --force -rltWDEgop --delete --stats --info=progress2 \
    --exclude '.gvfs' \
    --exclude '/boot' \
    --exclude '/dev' \
    --exclude '/media' \
    --exclude '/mnt' \
    --exclude '/proc' \
    --exclude '/run' \
    --exclude '/sys' \
    --exclude '/tmp' \
    --exclude 'lost\+found' \
    // $ROOT_MOUNT

  for i in boot dev media mnt proc run sys; do
    if [ ! -d $ROOT_MOUNT/$i ]; then
      mkdir $ROOT_MOUNT/$i
    fi
  done

  if [ ! -d $ROOT_MOUNT/boot/efi ]; then
    mkdir $ROOT_MOUNT/boot/efi
  fi

  if [ ! -d $ROOT_MOUNT/tmp ]; then
    mkdir $ROOT_MOUNT/tmp
    chmod a+w $ROOT_MOUNT/tmp
  fi
}


mv_rootfs() {
  origin_root=$(df | grep /$ | awk '{print $1}')
  if [ "$origin_root" == "" ]; then
    echo '*** Cannot find the rootfs'
    exit 1
  fi

  echo -e "Origin rootfs: ${origin_root}\n"
  echo "Please select the destination nvme device"

  nvme_dev=$(lsblk -d | grep nvme | awk '{print $1}')
  select dst in $nvme_dev; do
    echo -e "You have chosen ${dst}\n"
    if [ "$dst" == "" ]; then
      echo '*** Invalid option'
    else
      break
    fi
  done

  confirm "This operation will erase your ${dst}'s data, are you sure?" "abort"
  confirm "Please confirm again, whether to continue?" "abort"

  echo -e "\nStart to move rootfs to ${dst}"
  echo -e "Please wait for a while...\n"

  fdisk --wipe always /dev/${dst} > /dev/null << EOF
g
n
1
2048

w
EOF

  mkfs.ext4 /dev/${dst}p1 > /dev/null 2>&1
  mount /dev/${dst}p1 $ROOT_MOUNT
  rsync_rootfs

  old_root_uuid=$(blkid -o export ${origin_root} | grep ^UUID | cut -b 6-100)
  new_root_uuid=$(blkid -o export /dev/${dst}p1 | grep ^UUID | cut -b 6-100)

  _origin_root=$(echo ${origin_root} | cut -d '/' -f 3)
  sed -i "s/${_origin_root}/${dst}p1/g" /boot/extlinux/extlinux.conf
  sed -i "s/$old_root_uuid/$new_root_uuid/g" $ROOT_MOUNT/etc/fstab

  umount $ROOT_MOUNT
  echo -e "\nMove rootfs to ${dst} successfully."
  echo "Please reboot your Milk-V Pionner. Have Fun."
}


print_help() {
  echo "------------------------"
  echo "  The script is to help you move Milk-V Pioneer rootfs to NVMe ssd."
  echo "  ** Be careful, this will erase your ssd when you select a target device."
  echo -e "------------------------\n"
}


if [ "$DISTRO" == "fedora" ]; then
  print_help
  mv_rootfs
else
  echo '*** The script is not available on the distro'
  exit 0
fi
