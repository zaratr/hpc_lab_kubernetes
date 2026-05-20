#!/usr/bin/env bash
set -euo pipefail

role="${HPC_ROLE:-${1:-login}}"

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local label="$3"
  local timeout="${4:-240}"
  local start
  start="$(date +%s)"

  until timeout 2 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1; do
    if (( "$(date +%s)" - start > timeout )); then
      echo "[ERROR] Timed out waiting for ${label} at ${host}:${port}" >&2
      return 1
    fi
    sleep 2
  done
}

install_config() {
  if [[ -f /config/slurm.conf ]]; then
    install -o root -g root -m 0644 /config/slurm.conf /etc/slurm/slurm.conf
  fi

  if [[ -f /config/slurmdbd.conf ]]; then
    install -o slurm -g slurm -m 0600 /config/slurmdbd.conf /etc/slurm/slurmdbd.conf
  fi

  if [[ -f /config/munge.key ]]; then
    install -o munge -g munge -m 0400 /config/munge.key /etc/munge/munge.key
  fi
}

prepare_runtime() {
  mkdir -p /run/munge /run/slurm /var/log/munge /var/log/slurm \
    /var/spool/slurm/ctld /var/spool/slurm/d /hpc-workspace \
    /home/hpcuser/work /projects /scratch /logs/jobs
  chown -R munge:munge /run/munge /var/log/munge
  chown -R slurm:slurm /var/log/slurm /var/spool/slurm
  chown -R hpcuser:hpcuser /home/hpcuser /hpc-workspace /projects /scratch /logs || true

  install_config

  if [[ ! -f /etc/munge/munge.key ]]; then
    echo "[ERROR] Missing /etc/munge/munge.key; mount the munge-key secret at /config/munge.key" >&2
    return 1
  fi

  munged --force
}

prepare_runtime

case "${role}" in
  slurmdbd)
    echo "[STARTING] Launching Slurm Accounting Daemon..."
    wait_for_tcp mariadb-internal 3306 MariaDB 240
    exec slurmdbd -D -vvv
    ;;
  slurmctld)
    echo "[STARTING] Launching Central Cluster Controller..."
    wait_for_tcp hpc-scheduler-core 6819 slurmdbd 240
    exec slurmctld -D -vvv
    ;;
  compute)
    echo "[STARTING] Initializing Worker Node Blade..."
    wait_for_tcp hpc-scheduler-core 6817 slurmctld 240
    exec slurmd -D -vvv
    ;;
  login)
    echo "[STARTING] Exposing Interactive Workspace..."
    wait_for_tcp hpc-scheduler-core 6817 slurmctld 240
    ssh-keygen -A
    exec /usr/sbin/sshd -D
    ;;
  *)
    echo "[ERROR] Invalid HPC_ROLE specified: ${role}" >&2
    exit 1
    ;;
esac
