#!/bin/bash
#SBATCH --job-name=ior_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=./../results/podman_ior_mdtest_%j.out

# Create test directory
CONTAINER_IMAGE="localhost/ior-benchmark:latest"

BASE_DIR=$(pwd)/..

TEST_DIR=$BASE_DIR/ior-${SLURM_JOB_ID}
TMPDIR=/tmp/podman-mpirun-$SLURM_JOB_ID

mkdir -p "$TEST_DIR"
mkdir -p "$TMPDIR"

MPIRUN="mpirun \
    --map-by ppr:4:node \
    --mca orte_tmpdir_base $TMPDIR \
    --mca btl self,tcp \
    --bind-to socket"

PODMAN_RUN="podman run \
            --rm \
            --env-host \
            -v $TMPDIR:$TMPDIR \
            -v $TEST_DIR:/mnt/sharedir \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            $CONTAINER_IMAGE"

source ./bench_lib.sh

bench_start podman_ior


sleep 2
echo "========================================="
echo "IOR Write Test"
echo "========================================="

$MPIRUN $PODMAN_RUN /opt/ior/bin/ior -k -w -o /mnt/sharedir/ior_testfile -t 1m -b 16m -s 16

echo ""
echo "========================================="
echo "IOR Read Test"
echo "========================================="
$MPIRUN $PODMAN_RUN /opt/ior/bin/ior -r -o /mnt/sharedir/ior_testfile -t 1m -b 16m -s 16


echo "========================================="
echo "MDTEST"
echo "========================================="

$MPIRUN $PODMAN_RUN /opt/ior/bin/mdtest -d /mnt/sharedir/mdtest -n 1000 -i 3 -u -L -F

bench_end
echo ""
echo "========================================="
echo "Completed"
echo "========================================="
# Cleanup
rm -rf $TEST_DIR
