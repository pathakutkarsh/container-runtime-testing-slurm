#!/bin/bash
#SBATCH --job-name=charliecloud_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=./../results/charliecloud_ior_benchmark_%j.out

BASE_DIR=$(pwd)/..
TEST_DIR=$BASE_DIR/ior_mdtest_charliecloud

source ./bench_lib.sh

MPIRUN="mpirun \
    --map-by ppr:4:node \
    --bind-to socket"

CHARLIECLOUD_RUN="ch-run \
                  -b $TEST_DIR:$TEST_DIR \
                  $BASE_DIR/charliecloud/ior_mdtest_charliecloud --"


mkdir -p "$TEST_DIR"

bench_start charliecloud_ior

echo "========================================="
echo "IOR WRITE TEST "
echo "========================================="

$MPIRUN $CHARLIECLOUD_RUN /opt/ior/bin/ior -a POSIX -w -k -o $TEST_DIR/ior_testfile -b 128m -t 512k -s 8 -C -Q 1

echo "========================================="
echo "IOR READ TEST "
echo "========================================="

$MPIRUN $CHARLIECLOUD_RUN /opt/ior/bin/ior -a POSIX -r -o $TEST_DIR/ior_testfile -b 128m -t 512k -s 8 -C -Q 1

echo "========================================="
echo "MDTEST "
echo "========================================="

$MPIRUN $CHARLIECLOUD_RUN /opt/ior/bin/mdtest -d $TEST_DIR/mdtest -n 1000 -i 3 -u -L -F

bench_end

echo ""
echo "========================================="
echo "Benchmark completed successfully."
echo "========================================="
# rm -rf $TEST_DIR