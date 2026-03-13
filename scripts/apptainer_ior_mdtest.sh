#!/bin/bash
#SBATCH --job-name=apptainer_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=./../results/apptainer_ior_benchmark_%j.out

BASE_DIR=$(pwd)/..
CONTAINER=$BASE_DIR/apptainer/ior.sif
TEST_DIR=$BASE_DIR/ior_mdtest_apptainer 

mkdir -p "$TEST_DIR"

source ./bench_lib.sh

MPIRUN="mpirun \
    --map-by ppr:4:node \
    --mca btl self,tcp \
    --bind-to socket"

APPTAINER_RUN="apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    --bind $TEST_DIR:$TEST_DIR \
    $CONTAINER"

bench_start apptainer_ior

echo "========================================="
echo "IOR WRITE TEST (Apptainer)"
echo "========================================="
$MPIRUN $APPTAINER_RUN \
    ior -a POSIX -w -k -o $TEST_DIR/ior_testfile -b 128m -t 512k -s 8 -C -Q 1

echo "========================================="
echo "IOR READ TEST (Apptainer)"
echo "========================================="
$MPIRUN $APPTAINER_RUN \
    ior -a POSIX -r -o $TEST_DIR/ior_testfile -b 128m -t 512k -s 8 -C -Q 1

echo "========================================="
echo "MDTEST (Apptainer)"
echo "========================================="
$MPIRUN $APPTAINER_RUN \
    mdtest -d $TEST_DIR/mdtest -n 1000 -i 3 -u -L

bench_end

echo ""
echo "========================================="
echo "Completed"
echo "========================================="

rm -rf $TEST_DIR