#!/bin/bash
#SBATCH --job-name=osu_benchmarks
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=01:30:00
#SBATCH --output=./../results/slurm_osu_results_%j.out

source ./bench_lib.sh

bench_start slurm

BASE_DIR=$(pwd)/../

echo "========================================="
echo "OSU Latency Test"
echo "========================================="
mpirun -np 2  $BASE_DIR/osu-micro-benchmarks-7.4/c/mpi/pt2pt/standard/osu_latency

echo ""
echo "========================================="
echo "OSU Bandwidth Test"
echo "========================================="
mpirun -np 2  $BASE_DIR/osu-micro-benchmarks-7.4/c/mpi/pt2pt/standard/osu_bw

echo ""
echo "========================================="
echo "OSU Bidirectional Bandwidth Test"
echo "========================================="
mpirun -np 2  $BASE_DIR/osu-micro-benchmarks-7.4/c/mpi/pt2pt/standard/osu_bibw

echo ""
echo "========================================="
echo "OSU Allreduce Test"
echo "========================================="
mpirun -np 2  $BASE_DIR/osu-micro-benchmarks-7.4/c/mpi/collective/blocking/osu_allreduce

bench_end

echo ""
echo "========================================="
echo "Completed"
echo "========================================="
