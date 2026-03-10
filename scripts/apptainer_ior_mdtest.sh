#!/bin/bash
#SBATCH --job-name=apptainer_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=./../results/apptainer_ior_benchmark_%j.out

BASE_DIR=$(pwd)/../
TEST_DIR=$BASE_DIR/osu_apptainer
CONTAINER=$BASE_DIR/apptainer/ior.sif

mkdir -p $TEST_DIR

source ./bench_lib.sh

bench_start apptainer_osu


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
    mdtest -d $TEST_DIR/mdtest -n 1000 -i 3 -u -L -
    
bench_end
echo ""
echo "========================================="
echo "Completed"
echo "========================================="
# Cleanup
rm -rf $TEST_DIR
