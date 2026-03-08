#!/bin/bash
#SBATCH --job-name=charlecloud_osu
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=/home/cloud/shared_dir/results/charliecloud_osu_benchmark_%j.out

BASE_DIR=/home/cloud/shared_dir

echo "Start Time: $(date)"
echo "========================================="
echo "OSU Latency Test (Using Host MPI)"
echo "========================================="

# Use host MPI (mpirun from system), but run OSU binary inside container
mpirun -np 2 \
  --bind-to core \
  --mca btl self,tcp \
ch-run /home/cloud/shared_dir/charliecloud/osu-benchmarks -- /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency

echo ""
echo "========================================="
echo "OSU Bandwidth Test"
echo "========================================="

mpirun -np 2 \
  --bind-to core \
  --mca btl self,tcp \
ch-run /home/cloud/shared_dir/charliecloud/osu-benchmarks -- /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw

echo ""
echo "========================================="
echo "OSU Bidirectional Bandwidth Test"
echo "========================================="

mpirun -np 2 \
  --bind-to core \
  --mca btl self,tcp \
ch-run /home/cloud/shared_dir/charliecloud/osu-benchmarks -- /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bibw

echo ""
echo "========================================="
echo "OSU Allreduce Test"
echo "========================================="

mpirun -np 2 \
  --bind-to core \
  --mca btl self,tcp \
ch-run /home/cloud/shared_dir/charliecloud/osu-benchmarks -- /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce

echo "End Time: $(date)"
echo ""
echo "========================================="
echo "Benchmark completed successfully."
echo "========================================="
