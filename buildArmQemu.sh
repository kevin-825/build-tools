#!/bin/bash

ARM=/hst_root/mnt/wsl/vhd0/opt/arm
sudo mkdir -p ${ARM}

ARM_QEMU=${ARM}/arm_qemu
sudo mkdir -p $ARM_QEMU

#git clone https://github.com/qemu/qemu.git
cd qemu
git checkout v10.1.3

mkdir -p build_arm && cd build_arm
../configure \
  --target-list=arm-linux-user,armeb-linux-user,aarch64-linux-user,aarch64_be-linux-user,arm-softmmu,aarch64-softmmu \
  --prefix=$ARM_QEMU

make -j$(nproc)
sudo make install

script=add2path.sh
touch ./$script
echo export PATH=\"\$PATH:$ARM_QEMU/bin\" > ./$script
cat ./$script
sudo cp ./$script ${ARM}


#../configure --help | grep arm
#../configure --prefix=/opt/qemu-riscv --target-list=arm-linux-user,armeb-linux-user,arm-softmmu
#../configure --help | grep arm*user
#../configure --help | grep arm**user
#../configure --help | grep arm
#../configure --help | grep [arm*user]
#../configure --help | grep arm[*]user
#../configure --help | grep arm?*user
#../configure --prefix=/opt/qemu-riscv --target-list=arm-linux-user,armeb-linux-user,arm-softmmu

#../configure --prefix=/opt/qemu-arm --target-list=arm-linux-user,armeb-linux-user,arm-softmmu

