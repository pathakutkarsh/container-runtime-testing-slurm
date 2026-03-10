#!/bin/bash
#SBATCH --job-name=apptainer_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:30:00
#SBATCH --output=./../results/apptainer_osu_benchmark_%j.out

BASE_DIR=$(pwd)/../
TMPDIR="/tmp/apptainer-mpirun-$$"
CONTAINER=$BASE_DIR/apptainer/osu.sif

mkdir -p $TMPDIR
source ./bench_lib.sh

# Use host MPI libs inside container
HOST_MPI_DIR=$(dirname $(which mpirun))/..
HOST_MPI_LIBDIR=$(find $HOST_MPI_DIR -name "libmpi.so*" -printf "%h\n" 2>/dev/null | head -1)

APPTAINER_RUN="apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    --bind $TMPDIR:$TMPDIR \
    --bind /dev/shm:/dev/shm \
    --bind $HOST_MPI_DIR:$HOST_MPI_DIR \
    ${HOST_MPI_LIBDIR:+--bind $HOST_MPI_LIBDIR:$HOST_MPI_LIBDIR} \
    --env LD_LIBRARY_PATH=$HOST_MPI_LIBDIR:$LD_LIBRARY_PATH \
    $CONTAINER"

MPIRUN="mpirun \
    --np 2 \
    --bind-to core \
    --mca btl self,tcp \
    --mca orte_tmpdir_base $TMPDIR"

bench_start apptainer_osu

echo "========================================="
echo "OSU Latency Test (Using Host MPI)"
echo "========================================="
$MPIRUN $APPTAINER_RUN /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency

echo ""
echo "========================================="
echo "OSU Bandwidth Test"
echo "========================================="
$MPIRUN $APPTAINER_RUN /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw

echo ""
echo "========================================="
echo "OSU Bidirectional Bandwidth Test"
echo "========================================="
$MPIRUN $APPTAINER_RUN /usr/local/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bibw

echo ""
echo "========================================="
echo "OSU Allreduce Test"
echo "========================================="
$MPIRUN $APPTAINER_RUN /usr/local/libexec/osu-micro-benchmarks/mpi/collective/osu_allreduce

bench_end

echo ""
echo "========================================="
echo "Completed"
echo "========================================="

rm -rf $TMPDIR