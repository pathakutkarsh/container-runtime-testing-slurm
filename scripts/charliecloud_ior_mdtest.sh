#!/bin/bash
#SBATCH --job-name=charliecloud_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=./../results/charliecloud_ior_benchmark_%j.out

BASE_DIR=$(pwd)/..
TEST_DIR=$BASE_DIR/ior_mdtest_charliecloud
TMPDIR=/tmp/charliecloud-mpirun-$SLURM_JOB_ID

mkdir -p "$TEST_DIR"
mkdir -p "$TMPDIR"


source ./bench_lib.sh

MPIRUN="mpirun \
    --map-by ppr:4:node \
    --mca orte_tmpdir_base $TMPDIR \
    --mca btl self,tcp \
    --bind-to socket"

CHARLIECLOUD_RUN="ch-run \
                  -b $TEST_DIR:/mnt \
                  -b $TMPDIR:$TMPDIR \
                  $BASE_DIR/charliecloud/ior_mdtest_charliecloud --"



bench_start charliecloud_ior

echo "========================================="
echo "IOR WRITE TEST "
echo "========================================="

$MPIRUN $CHARLIECLOUD_RUN /opt/ior/bin/ior -k -w -o /mnt/ior_testfile -t 1m -b 16m -s 16

echo "========================================="
echo "IOR READ TEST "
echo "========================================="

$MPIRUN $CHARLIECLOUD_RUN /opt/ior/bin/ior -r -o /mnt/ior_testfile -t 1m -b 16m -s 16

echo "========================================="
echo "MDTEST "
echo "========================================="

$MPIRUN $CHARLIECLOUD_RUN /opt/ior/bin/mdtest -d /mnt/mdtest -n 1000 -i 3 -u -L -F

bench_end

echo ""
echo "========================================="
echo "Benchmark completed successfully."
echo "========================================="
# rm -rf $TEST_DIR