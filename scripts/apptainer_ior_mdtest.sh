#!/bin/bash
# run_benchmark_apptainer.sh

#SBATCH --job-name=apptainer_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=/home/cloud/shared_dir/apptainer_ior_benchmark_%j.out

BASE_DIR=/home/cloud/shared_dir
TEST_DIR=$BASE_DIR/ior_mdtest_apptainer
CONTAINER=$BASE_DIR/apptainer/ior.sif

mkdir -p $TEST_DIR

echo "========================================="
echo "IOR WRITE TEST (Apptainer)"
echo "========================================="

# Apptainer with MPI - uses hybrid mode
mpirun \
  --bind-to core \
  --map-by ppr:2:node \
  apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    $CONTAINER \
    ior -a POSIX -w -k -o $TEST_DIR/ior_testfile -b 128m -t 512k -s 8 -C -Q 1

echo "========================================="
echo "IOR READ TEST (Apptainer)"
echo "========================================="

mpirun \
  --bind-to core \
  --map-by ppr:2:node \
  apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    $CONTAINER \
    ior -a POSIX -r -o $TEST_DIR/ior_testfile -b 128m -t 512k -s 8 -C -Q 1

echo "========================================="
echo "MDTEST (Apptainer)"
echo "========================================="

mpirun \
  --bind-to core \
  --map-by ppr:2:node \
  apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    $CONTAINER \
    mdtest -d $TEST_DIR/mdtest -n 1000 -i 3 -u -L -F