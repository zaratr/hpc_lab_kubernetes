FROM rockylinux:9

ARG TENSORFLOW_PACKAGE=tensorflow-cpu==2.15.1

# Unified Slurm/Kubernetes node image. Runtime role selection happens in entrypoint.sh.
RUN printf '%s\n' \
      'retries=5' \
      'timeout=60' \
      'minrate=1000' \
      'max_parallel_downloads=3' \
      'fastestmirror=True' \
      'skip_if_unavailable=True' \
      >> /etc/dnf/dnf.conf && \
    dnf -y --setopt=tsflags=nodocs --setopt=install_weak_deps=False install epel-release && \
    dnf -y --setopt=tsflags=nodocs --setopt=install_weak_deps=False groupinstall "Development Tools" && \
    dnf -y --setopt=tsflags=nodocs --setopt=install_weak_deps=False install \
      bash-completion \
      bind-utils \
      hostname \
      iproute \
      jq \
      less \
      lsof \
      mariadb \
      munge \
      munge-devel \
      munge-libs \
      ncurses \
      openssh-clients \
      openssh-server \
      openmpi \
      openmpi-devel \
      procps-ng \
      python3 \
      python3-pip \
      slurm \
      slurm-devel \
      slurm-perlapi \
      slurm-slurmctld \
      slurm-slurmd \
      slurm-slurmdbd \
      sudo \
      tar \
      time \
      vim-minimal \
      which && \
    python3 -m pip install --no-cache-dir --upgrade pip && \
    python3 -m pip install --no-cache-dir "${TENSORFLOW_PACKAGE}" mpi4py && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

RUN getent group slurm >/dev/null || groupadd -r slurm && \
    id slurm >/dev/null 2>&1 || useradd -r -g slurm -d /var/lib/slurm -s /sbin/nologin slurm && \
    groupadd -g 2000 hpcuser && \
    useradd -m -u 2000 -g 2000 -s /bin/bash hpcuser && \
    echo 'hpcuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/hpcuser && \
    chmod 0440 /etc/sudoers.d/hpcuser && \
    mkdir -p /etc/slurm /run/munge /run/slurm /var/log/munge /var/log/slurm \
      /hpc-workspace \
      /var/spool/slurm/ctld /var/spool/slurm/d /home/hpcuser/work /projects /scratch /logs/jobs && \
    chown -R munge:munge /run/munge /var/log/munge && \
    chown -R slurm:slurm /var/log/slurm /var/spool/slurm && \
    chown -R hpcuser:hpcuser /home/hpcuser /hpc-workspace /projects /scratch /logs

ENV PATH="/usr/lib64/openmpi/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/lib64/openmpi/lib:${LD_LIBRARY_PATH:-}"

WORKDIR /hpc-workspace

COPY docker/hpc-node/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22 6817 6818 6819

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
