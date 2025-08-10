#!/bin/bash
set -e
source ~/.bashrc
export PATH="$RISCV_NEWLIB/bin:$RISCV_PK/bin:$RISCV_ISA_SIM/bin:$RISCV_QEMU/bin:$PATH"

RISCV=/hst_root/mnt/wsl/vhd0/opt/riscv
sudo mkdir -p ${RISCV}

RISCV_PK=${RISCV}/riscv_pk
sudo mkdir -p $RISCV_PK

[ -d "riscv-pk" ] || git clone https://github.com/riscv/riscv-pk.git
cd riscv-pk
mkdir -p build_bare_metal && cd build_bare_metal
../configure --prefix=$RISCV_PK --host=riscv64-unknown-elf
make -j$(nproc)
sudo make install
cd ..

mkdir -p build_linux && cd build_linux
../configure --prefix=$RISCV_PK --host=riscv64-unknown-linux-gnu
make -j$(nproc)
sudo make install
