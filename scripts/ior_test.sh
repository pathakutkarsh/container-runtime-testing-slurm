#!/bin/bash
#SBATCH --job-name=ior_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=./../results/ior_results_%j.out

# Create test directory

BASE_DIR=$(pwd)/..

TEST_DIR=$BASE_DIR/ior_test
mkdir -p $TEST_DIR


MPIRUN="mpirun \
    --map-by ppr:4:node \
    --bind-to socket \
    --mca btl self,tcp"


source ./bench_lib.sh

bench_start slurm_ior


sleep 2
echo "========================================="
echo "IOR Write Test"
echo "========================================="
$MPIRUN ior -k -w -o $TEST_DIR/ior_testfile -t 1m -b 16m -s 16

echo ""
echo "========================================="
echo "IOR Read Test"
echo "========================================="
$MPIRUN ior -r -o $TEST_DIR/ior_testfile -t 1m -b 16m -s 16

echo "========================================="
echo "MDTEST (NFS)"
echo "========================================="

$MPIRUN mdtest -d $TEST_DIR/mdtest -n 1000 -i 3 -u -L -F

bench_end

echo ""
echo "========================================="
echo "Completed"
echo "========================================="

sleep 1
# Cleanup
rm -rf $TEST_DIR
