# Kubernetes Slurm HPC Lab

Nicky,

This lab is a proof-of-work version of a production HPC platform pattern: Kubernetes owns the infrastructure lifecycle, while Slurm remains the workload scheduler that engineers actually use for batch, MPI, EDA, and ML jobs.

The design keeps the important operational pieces visible:

- Slurm controller, accounting daemon, compute workers, and login node are separate Kubernetes workloads.
- MariaDB persists Slurm accounting state.
- Munge provides shared authentication between Slurm daemons.
- Slurm tracks EDA-style license pools with `Licenses=cadence:2,synopsys:2,siemens:1`.
- Compute workers are horizontally scalable through a pitch-style Kubernetes `Deployment`.
- The login workspace provides the user-facing shell for `sinfo`, `sbatch`, `squeue`, `sacct`, MPI smoke tests, and TensorFlow checks.

This is intentionally not a toy Kubernetes Job demo. Kubernetes is used for the platform substrate; Slurm is still the scheduler for HPC workloads.

## Layout

```text
hpc_lab_kubernetes/
|-- .gitignore
|-- README.md
|-- docker/
|   `-- hpc-node/
|       |-- Dockerfile
|       `-- entrypoint.sh
|-- config/
|   |-- slurm.conf
|   |-- slurmdbd.conf
|   `-- munge.key
`-- k8s/
    |-- 00-namespace.yaml
    |-- 01-database.yaml
    |-- 02-control-plane.yaml
    |-- 03-workers.yaml
    `-- 04-login-workspace.yaml
```

## Build

From this directory:

```bash
docker build -t zaratr/hpc-node:latest -f docker/hpc-node/Dockerfile .
```

For Docker Desktop Kubernetes, load is automatic because the local Docker daemon is shared. For kind or minikube, load the image into the cluster:

```bash
kind load docker-image zaratr/hpc-node:latest
```

## Deploy

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-database.yaml
kubectl apply -f k8s/02-control-plane.yaml
kubectl apply -f k8s/03-workers.yaml
kubectl apply -f k8s/04-login-workspace.yaml
```

Wait for the lab:

```bash
kubectl -n hpc-system get pods -w
```

Open a login shell:

```bash
kubectl -n hpc-system exec -it deploy/login-workspace -- bash
```

## Smoke Test

Inside the login pod:

```bash
sinfo
scontrol show lic
mpirun --allow-run-as-root -np 2 hostname
python3 - <<'PY'
import tensorflow as tf
print(tf.__version__)
print(tf.reduce_sum(tf.constant([1, 2, 3])).numpy())
PY
```

Submit a Slurm job:

```bash
cat > /home/hpcuser/mpi-smoke.sbatch <<'EOF'
#!/bin/bash
#SBATCH --job-name=mpi-smoke
#SBATCH --partition=eda
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --licenses=cadence:1
#SBATCH --time=00:05:00

mpirun --allow-run-as-root -np 2 hostname
python3 - <<'PY'
import tensorflow as tf
print("tensorflow", tf.__version__)
PY
EOF

sbatch /home/hpcuser/mpi-smoke.sbatch
squeue
sacct -X --format=JobID,JobName,State,Elapsed,AllocCPUS
```

## Scale Workers

The Slurm topology declares four worker nodes. Scale up to that limit:

```bash
kubectl -n hpc-system scale deployment hpc-compute-nodes --replicas=4
```

Scale back down:

```bash
kubectl -n hpc-system scale deployment hpc-compute-nodes --replicas=2
```

## CI

GitHub Actions builds the unified image on pushes and pull requests to `main` using:

```bash
docker build -t zaratr/hpc-node:latest -f docker/hpc-node/Dockerfile .
```

## Notes

- `config/munge.key` is a lab-only shared credential and must be replaced for any real environment.
- The manifests use `emptyDir` and simple PVCs to keep the lab portable. Production would use a real storage class, backup policy, network policy, and sealed/external secrets.
- `imagePullPolicy: IfNotPresent` assumes the image is built or loaded locally.

## Cleanup

```bash
kubectl delete namespace hpc-system
```
