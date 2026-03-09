#!/bin/bash
#SBATCH --job-name=osu-podman
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=1
#SBATCH --time=01:30:00
#SBATCH --output=./../results/podman_osu_results_%j.out

CONTAINER_IMAGE="localhost/osu-benchmarks:latest"


source ./bench_lib.sh

bench_start podman_osu

BASE_DIR=$(pwd)/../

echo "========================================="
echo "OSU Latency Test"
echo "========================================="
    mpirun -np 2 \
        --mca orte_tmpdir_base /tmp/podman-mpirun \
        podman run \
            --rm \
            --env-host \
            -v /tmp/podman-mpirun:/tmp/podman-mpirun \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \  
            $CONTAINER_IMAGE \
            osu_latency

echo ""
echo "========================================="
echo "OSU Bandwidth Test"
echo "========================================="
    mpirun -np 2 \
        --mca orte_tmpdir_base /tmp/podman-mpirun \
        podman run \
            --rm \
            --env-host \
            -v /tmp/podman-mpirun:/tmp/podman-mpirun \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            $CONTAINER_IMAGE \
            osu_bw

echo ""
echo "========================================="
echo "OSU Bidirectional Bandwidth Test"
echo "========================================="
    mpirun -np 2 \
        --mca orte_tmpdir_base /tmp/podman-mpirun \
        podman run \
            --rm \
            --env-host \
            -v /tmp/podman-mpirun:/tmp/podman-mpirun \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            $CONTAINER_IMAGE \
            osu_bibw

echo ""
echo "========================================="
echo "OSU Allreduce Test"
echo "========================================="
    mpirun -np 2 \
        --mca orte_tmpdir_base /tmp/podman-mpirun \
        podman run \
            --rm \
            --env-host \
            -v /tmp/podman-mpirun:/tmp/podman-mpirun \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            $CONTAINER_IMAGE \
            osu_allreduce

bench_end

echo ""
echo "========================================="
echo "Completed"
echo "========================================="
