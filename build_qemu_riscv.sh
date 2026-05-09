#!/bin/bash

RISCV=/hst_root/mnt/wsl/vhd0/opt/riscv
sudo mkdir -p ${RISCV}

RISCV_QEMU=${RISCV}/riscv_qemu
sudo mkdir -p $RISCV_QEMU

if [ ! -d "./qemu/.git" ]; then
    echo "QEMU not found. Cloning..."
    git clone https://github.com/qemu/qemu.git
else
    echo "QEMU already exists. Skipping clone."
fi
cd qemu
git checkout v11.0.0

mkdir -p build_riscv && cd build_riscv
../configure \
  --target-list=riscv32-softmmu,riscv64-softmmu,riscv32-linux-user,riscv64-linux-user \
  --prefix=$RISCV_QEMU

make -j$(nproc)
sudo make install
