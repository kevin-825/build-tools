#!/bin/bash
set -euo pipefail

#set default values
WORKDIR="/mnt/wsl/ramdisk5"
DRY_RUN=false
BACKUP_PATH=/home/kflyn/vhd1/tarballs
curDir=$(pwd)
FORCE=false


check_state_of_shadow_clone() {
    echo "--- Checking Parent Repo ---"
    git fetch --depth 1 -q
    LOCAL_HEAD=$(git rev-parse HEAD)
    REMOTE_HEAD=$(git rev-parse origin/master)

    if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
        echo "(!) Parent repo needs update: $LOCAL_HEAD -> $REMOTE_HEAD"
    else
        echo "(v) Parent repo is current."
    fi

    echo "--- Checking Submodules ---"
    # We use 'grep' to see if any line starts with '+' or '-'
    # Adding '|| true' ensures the script doesn't exit if grep finds nothing
    SUBMODULE_CHANGES=$(git submodule status --recursive | grep -E "^[+-]" || true)

    if [ -n "$SUBMODULE_CHANGES" ]; then
        echo "(!) Submodules need update/init:"
        echo "$SUBMODULE_CHANGES"
    else
        echo "(v) All submodules are in sync."
    fi
}


clone_repos_has_submodules() {
    local url="$1"
    local repo_main_dir_name="$2"
    local shadow_clone="$3"
    local src_backup_path="$4"
    
    local clone_option=""
    cd "$WORKDIR"

    if [ "$shadow_clone" == true ]; then
        clone_option="--depth 1"
    fi  
        
    if [ ! -d "$repo_main_dir_name" ]; then
        echo "Cloning $repo_main_dir_name ..."
        # FIX: Changed variable to $url and added directory name
        until git clone "$url" "$repo_main_dir_name" $clone_option; do
            echo "Clone failed, cleaning up and retrying..."
            rm -rf "$repo_main_dir_name" # FIX: Prevents "directory already exists" error on retry
            sleep 2
        done
        echo "$repo_main_dir_name clone successful"  
    else
        echo "$repo_main_dir_name already exists, skipping clone."
    fi

    cd "$repo_main_dir_name"
    echo "Syncing and fetching latest state..."
    git submodule sync --recursive
    
    if [ "$shadow_clone" == true ]; then
        # SHADOW LOGIC: Jump to the latest island
        git fetch --depth 1
        git reset --hard origin/master
    else
        # FULL CLONE LOGIC: Standard update
        git fetch
        # Use --ff-only to ensure we don't create "merge commits"
        # This keeps history clean like a shadow clone but is safer
        git merge --ff-only origin/master || git reset --hard origin/master
    fi

    echo "Updating submodule contents..."
    # This works for both; $clone_option will be "--depth 1" or empty
    until git submodule update --init --recursive $clone_option --jobs $(nproc) -f; do
        echo "Submodule update failed, retrying..."
    done
    echo " all submodules and main repo updated successfully"

    local current_commit=$(git rev-parse HEAD)
    check_state_of_shadow_clone

    cd "$WORKDIR"
    # --- GZ Backup Logic ---
    # Changed extension back to .gz
    local tarball_path="$src_backup_path/$repo_main_dir_name.tar.gz" 
    local tag_file="$tarball_path.tag"

    if [ "$FORCE" = false ] && [ -f "$tarball_path" ] && [ -f "$tag_file" ] && [ "$(cat "$tag_file")" == "$current_commit" ]; then
        echo "No Git changes detected. Skipping .gz creation."
    else
        if [ "$FORCE" = true ]; then echo "(!) Force flag detected. Re-creating backup regardless of state."; fi
        echo "Changes detected. Creating .tar.gz using pigz (all 12 threads)..."
        start_time=$(date +%s)
        
        cd "$WORKDIR"
        # --use-compress-program=pigz tells tar to use the parallel engine
        tar --use-compress-program=pigz -cf "$tarball_path" "$repo_main_dir_name"
        
        end_time=$(date +%s)
        echo "$current_commit" > "$tag_file"
        echo "Backup created with pigz in $((end_time - start_time)) seconds."
    fi
}

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -w, --workdir        Set the working directory"
    echo "  -b, --backup-path    Set the backup path"
    echo "  -f, --force          Force re-creation of the tarball backup"
    echo "  -h, --help           Show this help message"
    exit 0
}

argparse() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -w|--workdir) WORKDIR="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            -b|--backup-path) BACKUP_PATH="$2"; shift 2 ;;
            -f|--force) FORCE=true; shift ;; # Added this line
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown argument: $1"; exit 1 ;;
        esac
    done
}

copy_riscv_gnu_toolchain_src_into_workdir() {
    # Support both .tar.xz and .tar.gz

    local TARBALL="$1/riscv-gnu-toolchain.tar.gz"
    if [ -d "$WORKDIR/riscv-gnu-toolchain" ]; then
        echo "already exists, skipping copy."
        return 0
    fi

    if [ -n "$TARBALL" ]; then
        echo "Extracting $TARBALL..."
        
        # 1. Create a safe temporary extraction point
        mkdir -p "$WORKDIR/extract_tmp"
        local EXTRACT_TMP="$WORKDIR/extract_tmp"
        
        #export XZ_OPT="-T0"
        # 2. Extract (tar -axf auto-detects compression format)
        if tar --use-compress-program=pigz -xf "$TARBALL" -C "$EXTRACT_TMP"; then
            # 3. Find the directory inside the extracted content
            local FOUND_DIR=$(find "$EXTRACT_TMP" -maxdepth 2 -type d -name "riscv-gnu-toolchain" | head -n 1)
            echo
            echo "FOUND_DIR: $FOUND_DIR"
            echo 
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

riscv_gnu_toolchain_update_shadow_clone() {
    BACKUP_PATH_TOOLCHAIN_SRC="$BACKUP_PATH/shadow_clone"
    mkdir -p $BACKUP_PATH_TOOLCHAIN_SRC

    copy_riscv_gnu_toolchain_src_into_workdir $BACKUP_PATH_TOOLCHAIN_SRC
    #update source from remote repo and backup again
    clone_repos_has_submodules "https://github.com/riscv/riscv-gnu-toolchain" "riscv-gnu-toolchain" true $BACKUP_PATH_TOOLCHAIN_SRC

    #./build_riscv_newlib_toolchain.sh -w $WORKDIR -r --prefix /mnt/wsl/vhd0/opt/riscv/rv_gnu_toolchain_test
}


main() {
    argparse "$@"

    if [ ! -d "$WORKDIR" ]; then
        echo "working directory does not exist: $WORKDIR"
        echo " WORKDIR not set, please set it like this: -w|--workdir /mnt/wsl/ramdisk5 "
        exit 1
    fi

    myuser=$(id -u)
    mygrp=$(id -g)

    sudo chown -R "$myuser:$mygrp" "$WORKDIR"

    
    riscv_gnu_toolchain_update_shadow_clone
    
    #we can do other repo update here

    cd $curDir
}

main "$@"