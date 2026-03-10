#!/bin/bash
#SBATCH --job-name=ior_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --time=00:30:00
#SBATCH --output=./../results/podman_ior_mdtest_%j.out

# Create test directory
CONTAINER_IMAGE="localhost/ior-benchmark:latest"

TMPDIR="/tmp/podman-mpirun-${SLURM_JOB_ID}"
mkdir -p "$TMPDIR"

BASE_DIR=$(pwd)/..
TEST_DIR="/tmp/ior-${SLURM_JOB_ID}"
mkdir -p "$TEST_DIR"


source ./bench_lib.sh

bench_start podman_ior


sleep 2
echo "========================================="
echo "IOR Write Test"
echo "========================================="

    mpirun -np $SLURM_NTASKS \
        --mca orte_tmpdir_base "$TMPDIR" \
        --bind-to socket \
        podman run \
            --rm \
            --env-host \
            -v "$TMPDIR:$TMPDIR" \
            -v "$TEST_DIR:$TEST_DIR" \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            "$CONTAINER_IMAGE" \
            /opt/ior/bin/ior -k -w -o $TEST_DIR/ior_testfile -t 1m -b 16m -s 16

echo ""
echo "========================================="
echo "IOR Read Test"
echo "========================================="
    mpirun -np $SLURM_NTASKS \
        --mca orte_tmpdir_base "$TMPDIR" \
        --bind-to socket \
        podman run \
            --rm \
            --env-host \
            -v "$TMPDIR:$TMPDIR" \
            -v "$TEST_DIR:$TEST_DIR" \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            "$CONTAINER_IMAGE" \
            /opt/ior/bin/ior -r -o $TEST_DIR/ior_testfile -t 1m -b 16m -s 16


echo "========================================="
echo "MDTEST"
echo "========================================="

    mpirun -np $SLURM_NTASKS \
        --mca orte_tmpdir_base "$TMPDIR" \
        --bind-to socket \
        podman run \
            --rm \
            --env-host \
            -v "$TMPDIR:$TMPDIR" \
            -v "$TEST_DIR:$TEST_DIR" \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            "$CONTAINER_IMAGE" \
            /opt/ior/bin/mdtest -d $TEST_DIR/mdtest -n 1000 -i 3 -u -L -F

bench_end
echo ""
echo "========================================="
echo "Completed"
echo "========================================="
# Cleanup
rm -rf $TEST_DIR
