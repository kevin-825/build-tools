#!/bin/bash
set -euo pipefail

#set default values
WORKDIR="/mnt/wsl/ramdisk5"
INSTALL_PREFIX="/mnt/wsl/vhd0/opt/riscv/rv_gnu_toolchain_reloc"
TOOLCHAIN_URL="git@github.com:riscv-collab/riscv-gnu-toolchain.git"
LOCAL_TOOLCHAIN_SRC_PATH=""
DRY_RUN=false
SRC_READY=false
BUILD_IMAGE="kflyn825/rv_gnu_toolchain_builder:latest" # Change this to your prebuilt container name
save_src_path=/home/kflyn/vhd1
curDir=$(pwd)


copy_toolchain_src_into_workdir() {
    rm -rf "$WORKDIR/riscv-gnu-toolchain"
    if [ "$LOCAL_TOOLCHAIN_SRC_PATH" == "" ]; then
        echo " Please set the local toolchain source path of riscv-gnu-toolchain:"
        echo "  -s local_path_to/riscv-gnu-tool     "
        exit 1
    fi
    if [ -d "$LOCAL_TOOLCHAIN_SRC_PATH/riscv-gnu-toolchain" ]; then
        # Copy to temp, then move
        cp -r "$LOCAL_TOOLCHAIN_SRC_PATH/riscv-gnu-toolchain" "$WORKDIR/riscv_tmp"
        mv "$WORKDIR/riscv_tmp" "$WORKDIR/riscv-gnu-toolchain"
    fi


# Support both .tar.xz and .tar.gz
    local TARBALL=""
    if [ -f "$LOCAL_TOOLCHAIN_SRC_PATH/riscv-gnu-toolchain.tar.xz" ]; then
        TARBALL="$LOCAL_TOOLCHAIN_SRC_PATH/riscv-gnu-toolchain.tar.xz"
    elif [ -f "$LOCAL_TOOLCHAIN_SRC_PATH/riscv-gnu-toolchain.tar.gz" ]; then
        TARBALL="$LOCAL_TOOLCHAIN_SRC_PATH/riscv-gnu-toolchain.tar.gz"
    fi

    if [ -n "$TARBALL" ]; then
        echo "Extracting $TARBALL..."
        
        # 1. Create a safe temporary extraction point
        mkdir -p "$WORKDIR/extract_tmp"
        local EXTRACT_TMP="$WORKDIR/extract_tmp"
        
        # 2. Extract (tar -axf auto-detects compression format)
        if tar -axf "$TARBALL" -C "$EXTRACT_TMP"; then
            # 3. Find the directory inside the extracted content
            local FOUND_DIR=$(find "$EXTRACT_TMP" -maxdepth 2 -type d -name "riscv-gnu-toolchain" | head -n 1)
            
            if [ -n "$FOUND_DIR" ]; then
                mv "$FOUND_DIR" "$WORKDIR/riscv-gnu-toolchain"
                echo "Successfully extracted and moved riscv-gnu-toolchain to $WORKDIR"
                rm -rf "$EXTRACT_TMP"
            else
                echo "Error: riscv-gnu-toolchain directory not found inside the archive"
                rm -rf "$EXTRACT_TMP"
                exit 1
            fi
        else
            echo "Error: Extraction failed"
            rm -rf "$EXTRACT_TMP"
            exit 1
        fi
        
        # Clean up the empty tmp shell
        rm -rf "$EXTRACT_TMP"
    fi
}


compile_the_toolchain() {
    if [ "$DRY_RUN" == true ]; then
        echo "Dry run: skipping Docker build."
        return 0
    fi

    # 1. Setup the Forge Environment (Host Side)
    export LDFLAGS_FOR_HOST="-static-libgcc -static-libstdc++ -Wl,-rpath,'\$ORIGIN/../host_libs'"
    
    local GDB_FLAGS="--with-python=python3 \
                    --with-python-libdir='$INSTALL_PREFIX/lib' \
                    --with-expat=yes \
                    --with-system-gmp \
                    --with-system-readline \
                    --enable-tui \
                    --enable-64-bit-bfd \
                    --with-lzma=yes \
                    --enable-source-highlight \
                    --with-curses"

    # 2. The Build Command (Inside Docker)
    build_cmd_bash="
        set -e
        mkdir -p build-newlib && cd build-newlib
        
        ../configure --prefix=$INSTALL_PREFIX \
            --disable-linux --enable-multilib --enable-qemu-system \
            --with-languages=c,c++ --with-cmodel=medany --with-sim=gdb \
            --enable-plugins
        
        make -j\$(nproc) \
            GDB_CONF_FLAGS='$GDB_FLAGS' \
            LDFLAGS_FOR_HOST='$LDFLAGS_FOR_HOST'
            
        make install GDB_CONF_FLAGS='$GDB_FLAGS'

        # --- THE INTERNAL PACKING LOGIC ---
        PY_VER=\$(python3 -c 'import sys; print(f\"{sys.version_info.major}.{sys.version_info.minor}\")')
        PY_SYS_LIB_PATH=\$(python3 -c 'import sysconfig; print(sysconfig.get_path(\"stdlib\"))')
        PY_LIB_DIR=\"$INSTALL_PREFIX/lib/python\${PY_VER}\"

        echo \"Packing for GDB 17 (Python \${PY_VER})...\"
        HOST_LIBS_DIR=\"$INSTALL_PREFIX/host_libs\"
        mkdir -p \"\$HOST_LIBS_DIR\"
        mkdir -p \"\$PY_LIB_DIR\"

        # 1. Identify and copy Shared Libraries
        LIBS_LIST_FILE=\"\$HOST_LIBS_DIR/bundled_libs.txt\"
        > \"\$LIBS_LIST_FILE\"
        libs=\$(ldd $INSTALL_PREFIX/bin/riscv64-unknown-elf-gdb | grep '=> /' | awk '{print \$3}' | grep -vE 'libc\\.so|libm\\.so|libdl\\.so|libpthread\\.so|ld-linux')
        for lib in \$libs; do
            cp -L -v \"\$lib\" \"\$HOST_LIBS_DIR/\"
            basename \"\$lib\" >> \"\$LIBS_LIST_FILE\"
        done

        # 2. Copy Python Standard Library
        cp -r \${PY_SYS_LIB_PATH}/* \"\$PY_LIB_DIR/\"

        # 3. Inject FreeRTOS Python Helper
        cat <<RTOS_PY > \"$INSTALL_PREFIX/bin/freertos_helper.py\"
import gdb
class TaskList(gdb.Command):
    def __init__(self): super(TaskList, self).__init__(\"task-list\", gdb.COMMAND_USER)
    def invoke(self, arg, from_tty):
        try:
            curr = gdb.parse_and_eval(\"pxCurrentTCB\")
            print(f\"Current Task: {curr['pcTaskName'].string()}\")
        except: print(\"RTOS symbols not found.\")
TaskList()
RTOS_PY

        # 4. Generate the README.md
        cat <<README_EOF > \"\$HOST_LIBS_DIR/README.md\"
# GDB 17 Portability Layer

Toolchain: GCC 15 / GDB 17
Python: \${PY_VER}

## Manual Override
If relocation fails, run:
\\\`\\\`\\\`bash
export PYTHONHOME=\"$INSTALL_PREFIX\"
export LD_LIBRARY_PATH=\"\$HOST_LIBS_DIR:\\\$LD_LIBRARY_PATH\"
\\\`\\\`\\\`

## RTOS Support
To enable FreeRTOS awareness, run this inside GDB:
\\\`source $INSTALL_PREFIX/bin/freertos_helper.py\\\`
README_EOF
"

    # 3. Execution
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$WORKDIR":"$WORKDIR" \
        -v "$INSTALL_PREFIX":"$INSTALL_PREFIX" \
        -w "$WORKDIR/riscv-gnu-toolchain" \
        "$BUILD_IMAGE" \
        bash -c "$build_cmd_bash"
}

argparse() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -w|--workdir)
                WORKDIR="$2"
                shift 2
                ;;
            -p|--prefix)
                INSTALL_PREFIX="$2"
                shift 2
                ;;
            -s|--src-path)
                LOCAL_TOOLCHAIN_SRC_PATH="$2"
                shift 2
                ;;
            --dry-run)
              DRY_RUN=true
              shift
              ;;
            -r|--src-ready)
                SRC_READY=true
                shift
                ;;
            -h|--help)
                echo "This script builds the RISC-V Newlib Toolchain. Typical usage is build the toolchain"
                echo " in a RAM disk for speed and then install it to a persistent location."
                echo ""
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  -w, --workdir         Set the working directory for building the toolchain"
                echo "  -p, --prefix          Set the installation prefix path for the riscv-gnu-toolchain"
                echo "  -s, --src-path        Set the local toolchain source path of riscv-gnu-toolchain"
                echo "  -h, --help            Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
}


make_ready() {
    if [ ! -d "$WORKDIR" ]; then
        echo "working directory does not exist: $WORKDIR"
        echo " WORKDIR not set, please set it like this: -w|--workdir /mnt/wsl/ramdisk5 "
        exit 1
    fi
    if [ "$INSTALL_PREFIX" == "" ]; then
        echo " Please set the installation prefix path of riscv-gnu-toolchain:"
        echo "  -p|--prefix /opt/riscv "
        exit 1
    fi
    myuser=$(id -u)
    mygrp=$(id -g)
    sudo chown -R "$myuser:$mygrp" "$WORKDIR"
    # Prepare the install directory so the Docker user can write to it
    sudo mkdir -p "$INSTALL_PREFIX"
    sudo chown -R "$myuser:$mygrp" "$INSTALL_PREFIX"

    if [ -d "$save_src_path/riscv-gnu-toolchain" ] || \
       [ -f "$save_src_path/riscv-gnu-toolchain.tar.xz" ] || \
       [ -f "$save_src_path/riscv-gnu-toolchain.tar.gz" ]; then
        LOCAL_TOOLCHAIN_SRC_PATH="$save_src_path"
    else
        #echo "Warning: No valid source (dir or tarball) found in $save_src_path"
        echo ""
    fi
        
    if [ "$LOCAL_TOOLCHAIN_SRC_PATH" == "" ]; then
        echo " Please set the local toolchain source path :"
        echo "  -s local_path_to/riscv-gnu-toolchain "
        exit 1
    else
        if [ "$SRC_READY" == false ]; then
            copy_toolchain_src_into_workdir
        else
            echo "riscv-gnu-toolchain source is ready. No need to copy."
        fi
    fi
}

main() {
    argparse "$@"
    make_ready

    compile_the_toolchain
    echo ""
    echo "Compilation Done."

    cd $curDir
}

main "$@"
