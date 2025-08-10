#!/bin/bash
set -e

RISCV=/hst_root/mnt/wsl/vhd0/opt/riscv
sudo mkdir -p ${RISCV}

# Clone only if riscv-gnu-toolchain doesn't already exist
if [ ! -d "riscv-gnu-toolchain" ]; then
  echo "Cloning riscv-gnu-toolchain..."
  git clone https://github.com/riscv-collab/riscv-gnu-toolchain
else
  echo "riscv-gnu-toolchain already exists, skipping clone."
fi
cd riscv-gnu-toolchain
git submodule update --init gcc

RISCV_NEWLIB=${RISCV}/gnu_toolchain_newlib
mkdir -p build-newlib && cd build-newlib

GDB_NATIVE_FLAGS_EXTRA="--with-python=/usr --with-expat --with-system-readline"
GDB_TARGET_FLAGS_EXTRA="--with-python=/usr --with-expat --with-system-readline"

sudo ../configure \
  --prefix=$RISCV_NEWLIB \
  --disable-linux \
  --enable-multilib \
  --with-arch=rv64gc \
  --with-abi=lp64d \
  --with-cmodel=medany \
  --with-languages=c,c++

sudo make -j$(nproc)


cd ..
set -e

RISCV_LINUX=${RISCV}/gnu_toolchain_linux
mkdir -p build-linux && cd build-linux

GDB_NATIVE_FLAGS_EXTRA="--with-python=/usr --with-expat --with-system-readline"
GDB_TARGET_FLAGS_EXTRA="--with-python=/usr --with-expat --with-system-readline"

sudo ../configure \
  --prefix=$RISCV_LINUX \
  --enable-linux \
  --enable-multilib \
  --enable-default-pie \
  --enable-strip \
  --with-arch=rv64gc \
  --with-abi=lp64d \
  --with-cmodel=medany \
  --with-languages=c,c++ \
  --with-multilib-generator="rv64gc-lp64d;rv32gc-ilp32d"

sudo make -j$(nproc) linux
