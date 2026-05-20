#!/bin/bash
set -e

# Generate or verify secure munge token communication layers
remunge --force

case "$HPC_ROLE" in
    slurmdbd)
        echo "[STARTING] Launching Slurm Accounting Daemon..."
        exec slurmdbd -D -vvv
        ;;
    slurmctld)
        echo "[STARTING] Launching Central Cluster Controller..."
        mkdir -p /var/spool/slurmctld
        chown -R slurm:slurm /var/spool/slurmctld
        exec slurmctld -D -vvv
        ;;
    compute)
        echo "[STARTING] Initializing Worker Node Blade..."
        exec slurmd -D -vvv
        ;;
    login)
        echo "[STARTING] Exposing Interactive Workspace..."
        ssh-keygen -A
        exec /usr/sbin/sshd -D
        ;;
    *)
        echo "[ERROR] Invalid HPC_ROLE specified: $HPC_ROLE"
        exit 1
        ;;
esac