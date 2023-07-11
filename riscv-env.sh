#!/usr/bin/bash -e
AUTHOR='neko <setq@milkv.io>'
VERSION='0.10'

SCRIPT_NAME=$(basename $0)
HOST_DISTRO=`cat /etc/os-release | grep ^ID= | sed -e 's/ID\=//g'`

if [ $(id -u) != 0 ]; then
  echo -e "${SCRIPT_NAME} needs to be run as root.\n"
  exit 1
fi

rv_arch_image_url="https://archriscv.felixc.at/images/archriscv-20220727.tar.zst"
rv_ubuntu_image="ubuntu-22.10-preinstalled-server-riscv64+unmatched.img.xz"
rv_ubuntu_image_url="https://cdimage.ubuntu.com/releases/22.10/release/${rv_ubuntu_image}"
rv_fedora_image="fedora-disk-server_sophgo_sg2042-f38-20230523-014306.n.0-sda.raw.xz"
rv_fedora_image_url="http://openkoji.iscas.ac.cn/kojifiles/work/tasks/8061/1418061/${rv_fedora_image}"


confirm() {
  printf "\n%s [Y/n] " "$1"
  read resp
  if [ "$resp" == "Y" ] || [ "$resp" == "y" ] || [ "$resp" == "yes" ]; then
    return 0
  fi
  if [ "$2" == "abort" ]; then
    echo -e "Abort.\n"
    exit 0
  fi
  return 1
}


distro="ubuntu"
OLD_OPTIND=$OPTIND
while getopts "D:M:d:h" flag; do
  case $flag in
    D)
      directory="$OPTARG"
      ;;
    M)
      machine="$OPTARG"
      ;;
    d)
      distro="$OPTARG"
      ;;
    h)
      $OPTARG
      print_help="1"
      ;;
  esac
done
OPTIND=$OLD_OPTIND

if [ "$machine" == "" ]; then
  machine="${distro}-riscv64"
fi

if [ "$directory" == "" ]; then
  directory="${PWD}/${machine}"
fi


ubuntu_host() {
  commands="wget gzip zstd xz qemu-riscv64-static systemd-nspawn losetup kpartx"
  packages="wget gzip zstd xz-utils qemu-user-static systemd-container mount kpartx"
  need_packages=""

  idx=1
  for cmd in $commands; do
    if ! command -v $cmd > /dev/null; then
      pkg=$(echo "$packages" | cut -d " " -f $idx)
      printf "%-30s %s\n" "Command not found: $cmd", "package required: $pkg"
      need_packages="${need_packages} ${pkg}"
    fi
    ((++idx))
  done

  if [ "$need_packages" != "" ]; then
    confirm "Do you want to install the packages?" "abort"
    apt-get install -y --no-install-recommends $need_packages
    echo '--------------------'
  fi
}


arch_host() {
  commands="wget gzip zstd xz qemu-riscv64-static kpartx losetup"
  packages="wget gzip zstd xz qemu-user-static kpartx util-linux"
  need_packages="qemu-user-static-binfmt"

  idx=1
  for cmd in $commands; do
    if ! command -v $cmd > /dev/null; then
      pkg=$(echo "$packages" | cut -d " " -f $idx)
      printf "%-30s %s\n" "Command not found: $cmd", "package required: $pkg"
      need_packages="${need_packages} ${pkg}"
    fi
    ((++idx))
  done

  if [ "$need_packages" != "" ]; then
    confirm "Do you want to install the packages?" "abort"
    pacman -S $need_packages
    echo '--------------------'
  fi
}


arch_env() {
  _tmp=$(mktemp -d)
  mkdir -p ${directory} && rm -rf ${directory}/*

  wget -c ${rv_arch_image_url} -O ${_tmp}/arch.tar.zst
  tar -I zstd -xf ${_tmp}/arch.tar.zst -C ${directory}

  systemd-nspawn -D ${directory} -M ${machine} -a -U
}


copy_rootfs() {
  rv_image_url="$1"
  partition="$2"
  _tmp=$(mktemp -d)

  wget -c ${rv_image_url} -O ${_tmp}/rootfs.raw.xz
  xz -kdv ${_tmp}/rootfs.raw.xz

  loopdevice=$(losetup -f --show ${_tmp}/rootfs.raw)
  mapdevice="/dev/mapper/$(kpartx -va ${loopdevice} | sed -E 's/.*(loop[0-9]+)p.*/\1/g' | head -1)"

  mkdir ${_tmp}/rootfs
  mount ${mapdevice}${partition} ${_tmp}/rootfs
  mkdir -p ${directory} && rm -rf ${directory}
  cp -a ${_tmp}/rootfs ${directory}

  umount ${_tmp}/rootfs
  kpartx -d ${loopdevice}
  losetup -d ${loopdevice}
}


ubuntu_env() {
  copy_rootfs ${rv_ubuntu_image_url} "p1"
  systemd-nspawn -D ${directory} -M ${machine} -a -U
}


fedora_env() {
  copy_rootfs ${rv_fedora_image_url} "p3"
  systemd-nspawn -D ${directory} -M ${machine} -a -U
}


print_usage() {
  echo -e "Usage:\n  sudo ./${SCRIPT_NAME} [-M NAME|-d distro|-D PATH|-h]"
  echo "    -M  set the machine name for the container"
  echo "    -d  specify a distribution for the container"
  echo "    -D  specify the root directory for the container"
}


if [ "$print_help" == "1" ]; then
  print_usage
  exit 0
fi

if [ "$HOST_DISTRO" == "debian" ] || [ "$HOST_DISTRO" == "ubuntu" ]; then
  ubuntu_host
elif [ "$HOST_DISTRO" == "arch" ] || [ "$HOST_DISTRO" == "archlinux" ]; then
  arch_host
else
  echo "*** This script is not available on your distribution."
  exit 0
fi

if [ "$distro" == "ubuntu" ]; then
  ubuntu_env
elif [ "$distro" == "arch" ] || [ "$distro" == "archlinux" ]; then
  arch_env
elif [ "$distro" == "fedora" ]; then
  fedora_env
else
  echo "*** The ${distro} is not supported, please select ubuntu or fedora or archlinux."
  exit 0
fi
