#!/bin/bash
set -e
# these are parameters and can be changed to suit your needs
QEMU_INSTALL_PATH=/hst_root/mnt/wsl/vhd0/opt/qemu
QEMU_VERSION=11.1.2
QEMU_TARGET_LIST="\
riscv32-softmmu,riscv64-softmmu,riscv32-linux-user,riscv64-linux-user,\
arm-softmmu,aarch64-softmmu,arm-linux-user,armeb-linux-user,aarch64-linux-user,aarch64_be-linux-user,\
x86_64-softmmu,i386-softmmu,x86_64-linux-user,i386-linux-user,\
"
WGET_ARGS="-q --show-progress --progress=bar:force:noscroll"

#make sure the install path exists
sudo mkdir -p ${QEMU_INSTALL_PATH}

#make sure qemu source code is present
if [ ! -d "./qemu-${QEMU_VERSION}" ]; then
    if [ ! -f "qemu-${QEMU_VERSION}.tar.xz" ]; then
        echo "QEMU source code archive not found. Downloading..."
        wget ${WGET_ARGS} https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz
    else
        echo "QEMU source code archive already exists.Extracting..."
    fi
    tar -xf qemu-${QEMU_VERSION}.tar.xz
else
    echo "QEMU source code already exists. Skipping download."
fi

cd qemu-${QEMU_VERSION}


mkdir -p build_riscv && cd build_riscv
../configure \
  --target-list=$QEMU_TARGET_LIST \
  --prefix=$QEMU_INSTALL_PATH

make -j$(nproc)
sudo make install
