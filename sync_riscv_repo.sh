#!/bin/bash
set -eu

# Configuration
REPO_URL="https://github.com/riscv-collab/riscv-gnu-toolchain"
JOBS=$(nproc)

echo "Checking repository status..."

if [ ! -d ".git" ] && [ ! -d "riscv-gnu-toolchain" ]; then
    # --- PHASE 1: FIRST TIME CLONE ---
    echo "Action: Initializing Fresh Shallow Clone"
    
    # 1. Clone the main wrapper (Depth 1 = Latest snapshot only)
    git clone --depth 1 $REPO_URL
    cd riscv-gnu-toolchain

    # 2. Initialize and Pull Submodules
    # This grabs the actual code (GCC, Binutils, etc.) for the first time
    echo "Fetching submodules (Shallow)..."
    git submodule update --init --recursive --progress --depth 1 --jobs $JOBS 

else
    # --- PHASE 2: UPDATE (A MONTH LATER) ---
    echo "Action: Updating Existing Shallow Repository"
    
    # Ensure we are inside the directory
    if [ -d "riscv-gnu-toolchain" ]; then cd riscv-gnu-toolchain; fi

    # 1. Update the wrapper (Keep it shallow)
    echo "Updating main wrapper..."
    git fetch origin master --depth 1
    git reset --hard origin/master

    # 2. Sync and Update Submodules
    # This is critical for the "Month Later" part. 
    # It moves submodules to new versions without downloading history.
    echo "Updating submodules to new versions (Shallow)..."
    git submodule sync
    git submodule update --init --recursive --progress --depth 1 --jobs $JOBS
fi

echo "-------------------------------------------------------"
echo "Success! Your local code is now at the latest version."
echo "You can now run your build scripts."
echo "-------------------------------------------------------"
