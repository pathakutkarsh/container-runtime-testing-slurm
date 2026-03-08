#!/bin/bash
#SBATCH --job-name=ior_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH --time=00:30:00
#SBATCH --output=./results/ior/ior_results_%j.out

# Create test directory
TEST_DIR=/home/cloud/shared_dir/ior_test
mkdir -p $TEST_DIR

sleep 2
echo "========================================="
echo "IOR Write Test"
echo "========================================="
mpirun ior -w -o $TEST_DIR/ior_testfile -t 1m -b 16m -s 16

echo ""
echo "========================================="
echo "IOR Read Test"
echo "========================================="
mpirun ior -r -o $TEST_DIR/ior_testfile -t 1m -b 16m -s 16

# Cleanup
#rm -rf $TEST_DIR
