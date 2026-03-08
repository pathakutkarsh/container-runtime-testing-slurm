#!/bin/bash
#SBATCH --job-name=osu-podman
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=1
#SBATCH --time=01:30:00
#SBATCH --output=/home/cloud/shared_dir/results/podman_osu_results_%j.out

BASE_DIR=/home/cloud/shared_dir
CONTAINER_IMAGE="localhost/osu-benchmarks:latest"
TEST_DIR=$BASE_DIR/ior_mdtest_${SLURM_JOB_ID}
NODES=$(scontrol show hostname $SLURM_JOB_NODELIST | tr '\n' ' ')

mkdir -p $TEST_DIR
mkdir -p $TEST_DIR/logs

echo "========================================="
echo "Running OSU Benchmarks in containers"
echo "Nodes: $NODES"
echo "========================================="

# Create a hostfile for MPI
HOSTFILE=$TEST_DIR/hostfile.txt
rm -f $HOSTFILE
for node in $NODES; do
    echo "$node slots=1" >> $HOSTFILE
done

echo "Hostfile content:"
cat $HOSTFILE

# Function to run OSU benchmarks
run_osu_benchmark() {
    local test_name=$1
    local test_command=$2
    local log_prefix=$3
    
    echo ""
    echo "========================================="
    echo "OSU $test_name Test"
    echo "========================================="
    
    # Launch the MPI job using srun
    srun --mpi=pmi2 \
        --ntasks=$SLURM_NTASKS \
        --ntasks-per-node=1 \
        --output=$TEST_DIR/logs/${log_prefix}_node_%N_task_%t.log \
        --error=$TEST_DIR/logs/${log_prefix}_node_%N_task_%t.err \
        podman run --rm \
        --network host \
        --volume /home/cloud/shared_dir:/data:z \
        --volume $HOSTFILE:/etc/hostsfile:z \
        --env OMPI_ALLOW_RUN_AS_ROOT=1 \
        --env OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
        --env OMPI_MCA_plm=slurm \
        --env OMPI_MCA_btl_tcp_if_include=ens3 \
        --env OMPI_MCA_pml=ob1 \
        --env OMPI_MCA_btl=self,tcp \
        "${CONTAINER_IMAGE}" \
        /bin/sh -c "mpirun --allow-run-as-root --hostfile /etc/hostsfile -np 2 $test_command"
    
    # Combine logs per node
    for node in $NODES; do
        cat $TEST_DIR/logs/${log_prefix}_node_${node}_task_*.log > $TEST_DIR/logs/${log_prefix}_${node}.log 2>/dev/null || true
        cat $TEST_DIR/logs/${log_prefix}_node_${node}_task_*.err > $TEST_DIR/logs/${log_prefix}_${node}.err 2>/dev/null || true
        rm -f $TEST_DIR/logs/${log_prefix}_node_${node}_task_*.log $TEST_DIR/logs/${log_prefix}_node_${node}_task_*.err
    done
}

# Run each benchmark
run_osu_benchmark "Latency" "osu_latency" "podman_osu_latency"
run_osu_benchmark "Bandwidth" "osu_bw" "podman_osu_bandwidth"
run_osu_benchmark "Bidirectional Bandwidth" "osu_bibw" "podman_osu_bibw"
run_osu_benchmark "Allreduce" "osu_allreduce" "podman_osu_allreduce"

# Clean up
rm -f $HOSTFILE
rm -f ${BASE_DIR}/run_benchmark_${SLURM_JOB_ID}.sh

echo ""
echo "All benchmarks completed at $(date)"