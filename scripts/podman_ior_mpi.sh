#!/bin/bash
#SBATCH --job-name=ior_podman_root
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=2
#SBATCH --time=00:20:00
#SBATCH --output=/home/cloud/shared_dir/results/podman_ior_%j.out

BASE_DIR=/home/cloud/shared_dir
TEST_DIR=$BASE_DIR/ior_mdtest_${SLURM_JOB_ID}
IMAGE=74c151c4da98
mkdir -p $TEST_DIR

export OMPI_MCA_btl_vader_single_copy_mechanism=none
export OMPI_MCA_plm=slurm

echo "========================================="
echo "IOR MPI-IO TEST (mpirun outside container)"
echo "========================================="
srun -N 2 podman load -i /home/cloud/shared_dir/podman/ior-benchmark.tar
mpirun \
  --map-by ppr:2:node \
  podman run --rm \
    --network=host \
    --ipc=host \
    -v $TEST_DIR:/opt/ \
    $IMAGE \
    ior \
      -a MPIIO \
      -w -r \
      -b 512m \
      -t 1m \
      -s 4 \
      -F \
      -o /opt/ior_file