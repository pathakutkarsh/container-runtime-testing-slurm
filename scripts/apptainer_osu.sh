#!/bin/bash
#SBATCH --job-name=apptainer_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=/home/cloud/shared_dir/results/apptainer_osu_benchmark_%j.out

BASE_DIR=/home/cloud/shared_dir
TEST_DIR=$BASE_DIR/osu_apptainer
CONTAINER=$BASE_DIR/apptainer/osu.sif

mkdir -p $TEST_DIR
echo "Start Time: $(date)"
echo "========================================="
echo "OSU Latency Test (Using Host MPI)"
echo "========================================="

# Use host MPI (mpirun from system), but run OSU binary inside container
mpirun -np 2 \
  --bind-to core \
  --mca btl self,tcp \
  apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    $CONTAINER \
    osu_latency

echo ""
echo "========================================="
echo "OSU Bandwidth Test"
echo "========================================="

mpirun -np 2 \
  --bind-to core \
  --mca btl self,tcp \
  apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    $CONTAINER \
    osu_bw

echo ""
echo "========================================="
echo "OSU Bidirectional Bandwidth Test"
echo "========================================="

mpirun -np 2 \
  --bind-to core \
  --mca btl self,tcp \
  apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    $CONTAINER \
    osu_bibw

echo ""
echo "========================================="
echo "OSU Allreduce Test"
echo "========================================="

mpirun -np 2 \
  --bind-to core \
  --mca btl self,tcp \
  apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    $CONTAINER \
    osu_allreduce

echo "End Time: $(date)"
echo ""
echo "========================================="
echo "Benchmark completed successfully."
echo "========================================="
