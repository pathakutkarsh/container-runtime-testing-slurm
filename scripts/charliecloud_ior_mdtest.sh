#!/bin/bash
#SBATCH --job-name=charliecloud_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=/home/cloud/shared_dir/results/charliecloud_ior_benchmark_%j.out

BASE_DIR=/home/cloud/shared_dir
TEST_DIR=$BASE_DIR/ior_mdtest_charliecloud

export OMPI_MCA_btl=tcp,self
export OMPI_MCA_btl_tcp_if_include=ens3
export OMPI_MCA_orte_base_help_aggregate=0

mkdir -p $TEST_DIR

echo "Start Time: $(date)"
echo "========================================="
echo "IOR WRITE TEST "
echo "========================================="

# Apptainer with MPI - uses hybrid mode
mpirun \
  --bind-to core \
  --map-by ppr:2:node \
  ch-run -b $TEST_DIR:/mnt /home/cloud/shared_dir/charliecloud/ior-benchmark -- /opt/ior/bin/ior -a POSIX -w -k -o /mnt/ior_testfile -b 128m -t 512k -s 8 -C -Q 1

echo "========================================="
echo "IOR READ TEST "
echo "========================================="

mpirun \
  --bind-to core \
  --map-by ppr:2:node \
  ch-run -b $TEST_DIR:/mnt /home/cloud/shared_dir/charliecloud/ior-benchmark -- /opt/ior/bin/ior -a POSIX -r -o /mnt/ior_testfile -b 128m -t 512k -s 8 -C -Q 1

echo "========================================="
echo "MDTEST "
echo "========================================="

mpirun \
  --bind-to core \
  --map-by ppr:2:node \
  ch-run -b $TEST_DIR:/mnt /home/cloud/shared_dir/charliecloud/ior-benchmark -- /opt/ior/bin/mdtest -d /mnt/mdtest -n 1000 -i 3 -u -L -F

echo "End Time: $(date)"
echo ""
echo "========================================="
echo "Benchmark completed successfully."
echo "========================================="
rm -rf $TEST_DIR