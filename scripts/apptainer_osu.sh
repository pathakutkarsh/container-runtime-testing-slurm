#!/bin/bash
#SBATCH --job-name=apptainer_benchmark
#SBATCH --nodes=2
#SBATCH --time=00:30:00
#SBATCH --output=./../results/apptainer_osu_benchmark_%j.out


BASE_DIR=$(pwd)/../
TEST_DIR=$BASE_DIR/osu_apptainer
CONTAINER=$BASE_DIR/apptainer/osu.sif

mkdir -p $TEST_DIR

source ./bench_lib.sh

bench_start apptainer_osu

echo "========================================="
echo "OSU Latency Test (Using Host MPI)"
echo "========================================="

# Use host MPI (mpirun from system), but run OSU binary inside container
mpirun -np 2 \
  --bind-to core \
  apptainer exec \
  --net --pid --ipc \
    $CONTAINER \
    osu_latency

echo ""
echo "========================================="
echo "OSU Bandwidth Test"
echo "========================================="

mpirun -np 2 \
  --bind-to core \
  apptainer exec \
  --net --pid --ipc \
    $CONTAINER \
    osu_bw

echo ""
echo "========================================="
echo "OSU Bidirectional Bandwidth Test"
echo "========================================="

mpirun -np 2 \
  --bind-to core \
  apptainer exec \
  --net --pid --ipc \
    $CONTAINER \
    osu_bibw

echo ""
echo "========================================="
echo "OSU Allreduce Test"
echo "========================================="

mpirun -np 2 \
  --bind-to core \
  apptainer exec \
  --net --pid --ipc \
    $CONTAINER \
    osu_allreduce

bench_end

echo ""
echo "========================================="
echo "Completed"
echo "========================================="
