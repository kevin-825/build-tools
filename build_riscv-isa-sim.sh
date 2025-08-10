#!/bin/bash
set -e

RISCV=/hst_root/mnt/wsl/vhd0/opt/riscv
sudo mkdir -p ${RISCV}

RISCV_ISA_SIM=${RISCV}/riscv_isa_sim
sudo mkdir -p $RISCV_ISA_SIM

git clone https://github.com/riscv/riscv-isa-sim.git
cd riscv-isa-sim
mkdir -p build && cd build
../configure --prefix=$RISCV_ISA_SIM
make -j$(nproc)
sudo make install
