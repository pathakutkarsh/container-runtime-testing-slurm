#!/bin/bash
#SBATCH --job-name=podman_ior_simple
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=2
#SBATCH --time=00:30:00
#SBATCH --output=podman_simple_%j.out

BASE_DIR=/home/cloud/shared_dir
TEST_DIR=$BASE_DIR/ior_mdtest_${SLURM_JOB_ID}
CONTAINER_IMAGE=ior-benchmark:latest
NODES=$(scontrol show hostname $SLURM_JOB_NODELIST | tr '\n' ' ')

mkdir -p $TEST_DIR
mkdir -p $TEST_DIR/logs

echo "========================================="
echo "Running IOR and MDTEST in containers"
echo "Nodes: $NODES"
echo "========================================="

echo "========================================="
echo "IOR WRITE TEST"
echo "========================================="

# Run IOR write test with separate logs per node
srun --mpi=pmi2 \
    --ntasks=$SLURM_NTASKS \
    --ntasks-per-node=2 \
    --output=$TEST_DIR/logs/ior_write_node_%N_task_%t.log \
    --error=$TEST_DIR/logs/ior_write_node_%N_task_%t.err \
    podman run --rm \
    --network host \
    --volume /home/cloud/shared_dir:/data:z \
    --env OMPI_ALLOW_RUN_AS_ROOT=1 \
    --env OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    --env OMPI_MCA_plm=isolated \
    --env OMPI_MCA_btl=self,vader \
    --env OMPI_MCA_pml=ob1 \
    --env SLURM_LOCALID=$SLURM_LOCALID \
    --env SLURM_NODEID=$SLURM_NODEID \
    --env SLURM_PROCID=$SLURM_PROCID \
    "${CONTAINER_IMAGE}" \
    /bin/sh -c "echo 'Task \$SLURM_PROCID on node \$HOSTNAME (local id: \$SLURM_LOCALID)'; \
                ior \
                -a POSIX \
                -w \
                -k \
                -o /data/ior_mdtest_${SLURM_JOB_ID}/ior_testfile \
                -b 128m \
                -t 512k \
                -s 8 \
                -C \
                -Q 1"

# Combine logs per node
for node in $NODES; do
    cat $TEST_DIR/logs/ior_write_node_${node}_task_*.log > $TEST_DIR/logs/ior_write_${node}.log 2>/dev/null || true
    cat $TEST_DIR/logs/ior_write_node_${node}_task_*.err > $TEST_DIR/logs/ior_write_${node}.err 2>/dev/null || true
done

echo "IOR Write logs saved to: $TEST_DIR/logs/ior_write_*.log"

echo "========================================="
echo "IOR READ TEST"
echo "========================================="

# Run IOR read test with separate logs per node
srun --mpi=pmi2 \
    --ntasks=$SLURM_NTASKS \
    --ntasks-per-node=2 \
    --output=$TEST_DIR/logs/ior_read_node_%N_task_%t.log \
    --error=$TEST_DIR/logs/ior_read_node_%N_task_%t.err \
    podman run --rm \
    --network host \
    --volume /home/cloud/shared_dir:/data:z \
    --env OMPI_ALLOW_RUN_AS_ROOT=1 \
    --env OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    --env OMPI_MCA_plm=isolated \
    --env OMPI_MCA_btl=self,vader \
    --env OMPI_MCA_pml=ob1 \
    --env SLURM_LOCALID=$SLURM_LOCALID \
    --env SLURM_NODEID=$SLURM_NODEID \
    --env SLURM_PROCID=$SLURM_PROCID \
    "${CONTAINER_IMAGE}" \
    /bin/sh -c "echo 'Task \$SLURM_PROCID on node \$HOSTNAME (local id: \$SLURM_LOCALID)'; \
                ior \
                -a POSIX \
                -r \
                -k \
                -o /data/ior_mdtest_${SLURM_JOB_ID}/ior_testfile \
                -b 128m \
                -t 512k \
                -s 8 \
                -C \
                -Q 1"

# Combine logs per node
for node in $NODES; do
    cat $TEST_DIR/logs/ior_read_node_${node}_task_*.log > $TEST_DIR/logs/ior_read_${node}.log 2>/dev/null || true
    cat $TEST_DIR/logs/ior_read_node_${node}_task_*.err > $TEST_DIR/logs/ior_read_${node}.err 2>/dev/null || true
done

echo "IOR Read logs saved to: $TEST_DIR/logs/ior_read_*.log"

echo "========================================="
echo "MDTEST"
echo "========================================="

# Run MDTEST with separate logs per node
srun --mpi=pmi2 \
    --ntasks=$SLURM_NTASKS \
    --ntasks-per-node=2 \
    --output=$TEST_DIR/logs/mdtest_node_%N_task_%t.log \
    --error=$TEST_DIR/logs/mdtest_node_%N_task_%t.err \
    podman run --rm \
    --network host \
    --volume /home/cloud/shared_dir:/data:z \
    --env OMPI_ALLOW_RUN_AS_ROOT=1 \
    --env OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    --env OMPI_MCA_plm=isolated \
    --env OMPI_MCA_btl=self,vader \
    --env OMPI_MCA_pml=ob1 \
    --env SLURM_LOCALID=$SLURM_LOCALID \
    --env SLURM_NODEID=$SLURM_NODEID \
    --env SLURM_PROCID=$SLURM_PROCID \
    "${CONTAINER_IMAGE}" \
    /bin/sh -c "echo 'Task \$SLURM_PROCID on node \$HOSTNAME (local id: \$SLURM_LOCALID)'; \
                mdtest \
                -d /data/ior_mdtest_${SLURM_JOB_ID}/mdtest \
                -n 1000 \
                -i 3 \
                -u \
                -L \
                -F"

# Combine logs per node
for node in $NODES; do
    cat $TEST_DIR/logs/mdtest_node_${node}_task_*.log > $TEST_DIR/logs/mdtest_${node}.log 2>/dev/null || true
    cat $TEST_DIR/logs/mdtest_node_${node}_task_*.err > $TEST_DIR/logs/mdtest_${node}.err 2>/dev/null || true
done

echo "MDTEST logs saved to: $TEST_DIR/logs/mdtest_*.log"

# Cleanup individual task logs (optional)
# rm -f $TEST_DIR/logs/*_task_*.log $TEST_DIR/logs/*_task_*.err


echo "========================================="
echo "Benchmark Complete"
echo "========================================="
echo "Summary of log files:"
echo "======================"
for node in $NODES; do
    echo "Node: $node"
    echo "  IOR Write: $TEST_DIR/logs/ior_write_${node}.log"
    echo "  IOR Read:  $TEST_DIR/logs/ior_read_${node}.log"
    echo "  MDTEST:    $TEST_DIR/logs/mdtest_${node}.log"
done
echo "========================================="
 