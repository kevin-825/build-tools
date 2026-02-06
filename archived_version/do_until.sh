
cd ./riscv-gnu-toolchain

shell="
git submodule update --init llvm
"


until $shell; do
    echo " failed,  retrying..."
done

echo " Successfully done."

cd ..



