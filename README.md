# Kubernetes Slurm HPC Lab

This project is a pitch-ready Slurm-on-Kubernetes lab. Kubernetes owns the platform lifecycle, while Slurm remains the scheduler interface for HPC-style batch work.

Use this README from the host terminal, not from inside a workload container. `kubectl` is a host-side tool and is installed/configured by Docker Desktop Kubernetes.

## Target Architecture

- Namespace: `hpc-system`
- Unified node image: `zaratr/hpc-node:latest`
- Runtime role selector: `HPC_ROLE`
- MariaDB accounting endpoint: `mariadb-internal`
- Combined Slurm control plane: `hpc-scheduler-core`
- Worker StatefulSet: `hpc-compute-nodes`
- Interactive login deployment: `login-workspace`

## Layout

```text
hpc_lab_kubernetes/
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

## 1. Start Docker Desktop

Run from PowerShell:

```powershell
docker desktop start
docker desktop status
docker version
```

If Docker Desktop is already running, `docker desktop start` may report that it is already started. That is fine.

## 2. Enable Docker Desktop Kubernetes

Docker Desktop Kubernetes is created from the Docker Desktop UI, not reliably from a CLI command.

1. Open Docker Desktop.
2. Go to **Kubernetes**.
3. Select **Create cluster**.
4. Choose **kubeadm** for this lab.
5. Wait until Docker Desktop reports that Kubernetes is running.

Use **kubeadm** because this lab uses a locally built image. With Docker Desktop kubeadm, the local Docker image store is the simplest path.

## 3. Verify Kubernetes From Host

Run from PowerShell, not inside a container:

```powershell
kubectl config get-contexts
kubectl config use-context docker-desktop
kubectl config current-context
kubectl get nodes
```

Expected node check:

```text
NAME             STATUS   ROLES           ...
docker-desktop   Ready    control-plane    ...
```

If `kubectl config get-contexts` shows no contexts, Kubernetes has not finished creating. Wait, then run the commands again.

## 4. Build The Unified Image

Run from the repo root:

```powershell
cd C:\Users\zarat\Projects\hpc_lab_kubernetes
docker build -t zaratr/hpc-node:latest -f docker/hpc-node/Dockerfile .
docker images zaratr/hpc-node
```

Do not run `kind load docker-image ...` for Docker Desktop kubeadm. That command is only for a separate kind cluster.

## 5. Deploy The Lab

Run from the repo root:

```powershell
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-database.yaml
kubectl apply -f k8s/02-control-plane.yaml
kubectl apply -f k8s/03-workers.yaml
kubectl apply -f k8s/04-login-workspace.yaml
```

Watch startup:

```powershell
kubectl -n hpc-system get pods -w
```

In another terminal, inspect the objects:

```powershell
kubectl -n hpc-system get all
kubectl -n hpc-system get pvc
kubectl -n hpc-system describe deploy hpc-scheduler-core
kubectl -n hpc-system describe statefulset hpc-compute-nodes
kubectl -n hpc-system describe deploy login-workspace
```

## 6. Check Logs If Pods Are Not Ready

Run from PowerShell:

```powershell
kubectl -n hpc-system logs statefulset/hpc-mariadb
kubectl -n hpc-system logs deploy/hpc-scheduler-core -c slurmdbd
kubectl -n hpc-system logs deploy/hpc-scheduler-core -c slurmctld
kubectl -n hpc-system logs statefulset/hpc-compute-nodes -c worker-blade --tail=80
kubectl -n hpc-system logs deploy/login-workspace -c login --tail=80
```

Common checks:

```powershell
kubectl -n hpc-system get events --sort-by=.lastTimestamp
kubectl -n hpc-system describe pod -l app=hpc-scheduler-core
kubectl -n hpc-system describe pod -l app=hpc-compute-nodes
```

## 7. Enter The Login Workspace

Run from PowerShell:

```powershell
kubectl -n hpc-system exec -it deploy/login-workspace -- bash
```

You are now inside the Rocky Linux login pod. The following commands run inside that pod.

## 8. Scenario 1: Linux And Toolchain Orientation

Run inside the login pod:

```bash
cat /etc/os-release
whoami
id
hostname
pwd
ls -la /etc/slurm
ls -la /home/hpcuser
ls -la /projects /scratch
```

Inspect installed tooling:

```bash
which slurmctld slurmd slurmdbd sinfo squeue sbatch sacct scontrol
which mpirun
python3 --version
mpirun --version
slurmctld -V
slurmd -V
slurmdbd -V
```

Validate Python packages:

```bash
python3 - <<'PY'
import tensorflow as tf
import mpi4py
print("tensorflow", tf.__version__)
print("mpi4py", mpi4py.__version__)
print("tf_sum", tf.reduce_sum(tf.constant([1, 2, 3])).numpy())
PY
```

## 9. Scenario 2: Slurm Cluster Visibility

Run inside the login pod:

```bash
sinfo
squeue
scontrol show nodes
scontrol show partitions
scontrol show lic
```

Check accounting:

```bash
sacctmgr show cluster
sacct -X --format=JobID,JobName,State,Elapsed,AllocCPUS
```

If these commands fail, keep the terminal open and inspect the control-plane logs from PowerShell using the commands in section 6.

## 10. Scenario 3: OpenMPI Smoke Test

Run inside the login pod:

```bash
mpirun --allow-run-as-root -np 2 hostname
```

This verifies OpenMPI is present in the image. It does not require Slurm.

## 11. Scenario 4: Submit A Slurm Job

Run inside the login pod:

```bash
cat > /home/hpcuser/mpi-smoke.sbatch <<'EOF'
#!/bin/bash
#SBATCH --job-name=mpi-smoke
#SBATCH --partition=eda
#SBATCH --nodes=1
#SBATCH --ntasks=2
#SBATCH --licenses=cadence:1
#SBATCH --time=00:05:00

hostname
mpirun --allow-run-as-root -np 2 hostname
python3 - <<'PY'
import tensorflow as tf
print("tensorflow", tf.__version__)
print("sum", tf.reduce_sum(tf.constant([1, 2, 3])).numpy())
PY
EOF

sbatch /home/hpcuser/mpi-smoke.sbatch
squeue
```

After the job runs:

```bash
sacct -X --format=JobID,JobName,Partition,State,Elapsed,AllocCPUS,ReqTRES%40
```

## 12. Scenario 5: License-Pool Scheduling

Create a small array job that requests one Cadence license per task:

```bash
cat > /home/hpcuser/license-array.sbatch <<'EOF'
#!/bin/bash
#SBATCH --job-name=license-array
#SBATCH --partition=eda
#SBATCH --array=1-4
#SBATCH --licenses=cadence:1
#SBATCH --time=00:05:00

echo "task=${SLURM_ARRAY_TASK_ID} host=$(hostname)"
sleep 60
EOF

sbatch /home/hpcuser/license-array.sbatch
squeue
scontrol show lic
```

The Slurm config declares `cadence:2`, so only two tasks should be able to consume that license at the same time when scheduling is functioning.

## 13. Scenario 6: Scale Workers

Run from PowerShell:

```powershell
kubectl -n hpc-system scale statefulset hpc-compute-nodes --replicas=2
kubectl -n hpc-system get pods -l app=hpc-compute-nodes -w
```

Then check from the login pod:

```bash
sinfo
scontrol show nodes
```

Scale down from PowerShell:

```powershell
kubectl -n hpc-system scale statefulset hpc-compute-nodes --replicas=1
kubectl -n hpc-system get pods -l app=hpc-compute-nodes
```

## 14. Finish The Session

Exit the login pod:

```bash
exit
```

Stop or remove the Kubernetes lab from PowerShell:

```powershell
kubectl delete namespace hpc-system
```

## CI

GitHub Actions builds the unified image on pushes and pull requests to `main` using:

```bash
docker build -t zaratr/hpc-node:latest -f docker/hpc-node/Dockerfile .
```

## Notes

- `config/munge.key` is a lab-only shared credential and must be replaced for any real environment.
- The Kubernetes manifests are intentionally pitch-first and compact.
- Production would use external secrets, real persistent storage, network policies, image publishing, and hardened Slurm node identity management.
