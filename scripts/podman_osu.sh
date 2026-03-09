#!/bin/bash
#SBATCH --job-name=osu-podman
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --time=01:30:00
#SBATCH --output=./../results/podman_osu_results_%j.out

CONTAINER_IMAGE="localhost/osu-benchmarks:latest"

TMPDIR="/tmp/podman-mpirun-${SLURM_JOB_ID}"
mkdir -p "$TMPDIR"

source ./bench_lib.sh

bench_start podman_osu

BASE_DIR=$(pwd)/../

echo "========================================="
echo "OSU Latency Test"
echo "========================================="
    mpirun -np $SLURM_NTASKS \
        --mca orte_tmpdir_base "$TMPDIR" \
        podman run \
            --rm \
            --env-host \
            -v "$TMPDIR:$TMPDIR" \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            "$CONTAINER_IMAGE" \
            /usr/local/osu/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency

echo ""
echo "========================================="
echo "OSU Bandwidth Test"
echo "========================================="
    mpirun -np $SLURM_NTASKS \
        --mca orte_tmpdir_base "$TMPDIR" \
        podman run \
            --rm \
            --env-host \
            -v "$TMPDIR:$TMPDIR" \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            "$CONTAINER_IMAGE" \
            /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw

echo ""
echo "========================================="
echo "OSU Bidirectional Bandwidth Test"
echo "========================================="
    mpirun -np $SLURM_NTASKS \
        --mca orte_tmpdir_base "$TMPDIR" \
        podman run \
            --rm \
            --env-host \
            -v "$TMPDIR:$TMPDIR" \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            "$CONTAINER_IMAGE" \
            /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bibw

echo ""
echo "========================================="
echo "OSU Allreduce Test"
echo "========================================="
    mpirun -np $SLURM_NTASKS \
        --mca orte_tmpdir_base "$TMPDIR" \
        podman run \
            --rm \
            --env-host \
            -v "$TMPDIR:$TMPDIR" \
            --userns=keep-id \
            --net=host --pid=host --ipc=host \
            "$CONTAINER_IMAGE" \
            /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce

bench_end

echo ""
echo "========================================="
echo "Completed"
echo "========================================="
