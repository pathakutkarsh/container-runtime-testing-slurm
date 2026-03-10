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

MPIRUN="mpirun \
    --np $SLURM_NTASKS \
    --bind-to core \
    --mca btl self,tcp \
    --mca orte_tmpdir_base $TMPDIR"

APPTAINER_RUN="apptainer exec \
    --bind $BASE_DIR:$BASE_DIR \
    $CONTAINER"

bench_start apptainer_osu

echo "========================================="
echo "OSU Latency Test (Using Host MPI)"
echo "========================================="
$MPIRUN $APPTAINER_RUN osu_latency

echo ""
echo "========================================="
echo "OSU Bandwidth Test"
echo "========================================="
$MPIRUN $APPTAINER_RUN osu_bw

echo ""
echo "========================================="
echo "OSU Bidirectional Bandwidth Test"
echo "========================================="
$MPIRUN $APPTAINER_RUN osu_bibw

echo ""
echo "========================================="
echo "OSU Allreduce Test"
echo "========================================="
$MPIRUN $APPTAINER_RUN osu_allreduce

bench_end

echo ""
echo "========================================="
echo "Completed"
echo "========================================="

rm -rf $TMPDIR