#!/bin/bash
#SBATCH --job-name=nfs_io_benchmark
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=nfs_benchmark_%j.out

BASE_DIR=/home/cloud/shared_dir
TEST_DIR=$BASE_DIR/ior_mdtest
mkdir -p $TEST_DIR

echo "========================================="
echo "IOR WRITE TEST (NFS)"
echo "========================================="

mpirun \
  --bind-to core \
  --map-by ppr:2:node \
  ior \
  -a POSIX \
  -w \
  -k \
  -o $TEST_DIR/ior_testfile \
  -b 128m \
  -t 512k \
  -s 8 \
  -C \
  -Q 1

echo "========================================="
echo "IOR READ TEST (NFS)"
echo "========================================="

mpirun \
  --bind-to core \
  --map-by ppr:2:node \
  ior \
  -a POSIX \
  -r \
  -o $TEST_DIR/ior_testfile \
  -b 128m \
  -t 512k \
  -s 8 \
  -C \
  -Q 1

echo "========================================="
echo "MDTEST (NFS)"
echo "========================================="

mpirun \
  --bind-to core \
  --map-by ppr:2:node \
  mdtest \
  -d $TEST_DIR/mdtest \
  -n 1000 \
  -i 3 \
  -u \
  -L \
  -F
