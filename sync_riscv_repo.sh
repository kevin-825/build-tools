#!/bin/bash
set -e

REPO_URL="https://github.com/riscv-collab/riscv-gnu-toolchain"
JOBS=$(nproc)

if [ ! -d "riscv-gnu-toolchain/.git" ]; then
    git clone --depth 1 $REPO_URL
    cd riscv-gnu-toolchain
else
    if [ -d "riscv-gnu-toolchain" ]; then cd riscv-gnu-toolchain; fi
    git fetch origin master --depth 1
    git reset --hard origin/master
fi

# KILL ANY STUCK MERGES/REBASES
# This is what fixed your 'gost-engine' issue in the log
git submodule foreach --recursive git am --abort || true
git submodule foreach --recursive git rebase --abort || true
git submodule foreach --recursive git reset --hard
git submodule foreach --recursive git clean -fd

# THE FINAL SYNC
# --checkout forces Git to stop 'merging' and just 'overwrite' with the right files
git submodule update --init --recursive --progress --depth 1 --force --checkout --jobs $JOBS
