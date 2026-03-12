#!/bin/bash
#SBATCH --job-name=charlecloud_osu
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --time=00:30:00
#SBATCH --output=./../results/charliecloud_osu_benchmark_%j.out

BASE_DIR=$(pwd)/../

source ./bench_lib.sh

MPIRUN="mpirun \
    --np 2 \
    --bind-to core \
    --mca btl self,tcp"

CHARLIECLOUD_RUN="ch-run $BASE_DIR/charliecloud/osu-benchmarks --"

bench_start charliecloud_osu
echo "========================================="
echo "OSU Latency Test (Using Host MPI)"
echo "========================================="

# Use host MPI (mpirun from system), but run OSU binary inside container

$MPIRUN $CHARLIECLOUD_RUN /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency

echo ""
echo "========================================="
echo "OSU Bandwidth Test"
echo "========================================="

$MPIRUN $CHARLIECLOUD_RUN /home/cloud/shared_dir/charliecloud/osu-benchmarks -- /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw

echo ""
echo "========================================="
echo "OSU Bidirectional Bandwidth Test"
echo "========================================="

$MPIRUN $CHARLIECLOUD_RUN /home/cloud/shared_dir/charliecloud/osu-benchmarks -- /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bibw

echo ""
echo "========================================="
echo "OSU Allreduce Test"
echo "========================================="

$MPIRUN $CHARLIECLOUD_RUN /home/cloud/shared_dir/charliecloud/osu-benchmarks -- /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce


bench_end

echo ""
echo "========================================="
echo "Benchmark completed successfully."
echo "========================================="
