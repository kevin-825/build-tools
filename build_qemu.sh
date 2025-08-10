#!/bin/bash

RISCV=/hst_root/mnt/wsl/vhd0/opt/riscv
sudo mkdir -p ${RISCV}

RISCV_QEMU=${RISCV}/riscv_qemu
sudo mkdir -p $RISCV_QEMU

#git clone https://github.com/qemu/qemu.git
cd qemu
git checkout v10.0.3

mkdir -p build && cd build
../configure \
  --target-list=riscv32-softmmu,riscv64-softmmu,riscv32-linux-user,riscv64-linux-user \
  --prefix=$RISCV_QEMU

make -j$(nproc)
sudo make install
