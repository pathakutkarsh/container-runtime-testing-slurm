# Introduction

This project assumes you have access to atleast 2+ nodes for creating the slurm cluster.

You are able to access all the nodes with ssh.

Preferred OS:
Ubuntu 22.04.5 LTS

All the steps which needs to performed on all the nodes are marked as (all)

All the steps which needs to perfromed on only controller node are maked by (controller).

All the steps which needs to performed on worker nodesare marked as (worker)

# Setup Network

## 1. Upgrade nodes (all)

```bash
sudo apt update
sudo apt upgrade

```

## 2. Add master node public key (worker)

Add controller public key in authorized_keys of worker nodes.

authorized_keys can be found in ```$HOME/.ssh```

Make sure the controller node is able to ssh to all the worker nodes.
this can simply be done by using the ``` ssh <hostname or IP address> ```

## 3. Setting up /etc/hosts

```bash
# Adding values in templates so that it can sustain server restart
sudo nano /etc/hosts
# Add the values in the format on new lines 

# <IP address> <hostname>


# Make sure that all computers on the cluster have each other in their known hosts file.  
```

# Setup Munge

## 1. Adding munge on controller node (controller)

`sudo apt install munge libmunge2 libmunge-dev`

Check status of munge

munge -n | unmunge | grep STATUS

### Copying munge controller key
You should see something like ``` STATUS: SUCCESS ```. Now, you have Munge correctly installed and there should be a Munge key at ```/etc/munge/munge.key```. If you don't see one, then you should be able to create one manually by running the following command:

```bash
sudo /usr/sbin/mungekey
```

## 2. Installing munge key on workers (workers)

`sudo apt install munge libmunge2 libmunge-dev`

now copy munge key of controller on workers in ``` /etc/munge/munge.key ```

Make sure the munge directory has correct permissions

```bash
sudo chown -R munge: /etc/munge/ /var/log/munge/ /var/lib/munge/ /run/munge/
sudo chmod 0700 /etc/munge/ /var/log/munge/ /var/lib/munge/
sudo chmod 0755 /run/munge/
sudo chmod 0700 /etc/munge/munge.key
sudo chown -R munge: /etc/munge/munge.key

```

Now restart the munge controller

```bash
systemctl enable munge
systemctl restart munge

```

# Installing Slurm

## 1. Install slurm package (all)

```bash
sudo apt install slurm-wlm
```

## 2. Configure Slurm on controller (controller)

To configure Slurm on your controller node do the following.

Use slurm's handy configuration file generator located at `/usr/share/doc/slurmctld/slurm-wlm-configurator.html` to create your configuration file. You can open the configurator file with your browser.

You don't have to fill out all of the fields in the configuration tool since a lot of them can be left to their defaults. The following fields are the once we had to manually configure:

ClusterName: `<YOUR-CLUSTER-NAME>`

SlurmctldHost: `<CONTROLLER-NODE-NAME>`

NodeName: `<WORKER-NODE-NAME>[1-4]` (this would mean that you have four worker nodes called `<WORKER-NODE-NAME>1`, `<WORKER-NODE-NAME>2`, `<WORKER-NODE-NAME>3`, `<WORKER-NODE-NAME>4`)

Enter values for CPUs, Sockets, CoresPerSocket, and ThreadsPerCore according to  `lscpu` (run on a worker node computer)

ProctrackType: LinuxProc

Once you press the submit button at the bottom of the configuration tool your configuration file text will appear in your browser. Copy this text into a new /etc/slurm/slurm.conf file and save.

`sudo nano /etc/slurm/slurm.conf`

## 3. Starting slurm (controller)

```bash
systemctl enable slurmctld
systemctl restart slurmctld
```

## 4. Starting slurm (worker)

```bash
sudo systemctl status slurmd
sudo systemctl start slurmd
sudo systemctl enable slurmd
```

### Check if all nodes are working correctly (controller)

```bash
sinfo

#or

srun -N2 hostname
```

# Creating NFS server

## 1. Creating NFS server on controller (controller)

```bash
sudo apt install nfs-kernel-server
mkdir -p ${PREFERRED_DIRECTORY}/shared_dir
echo "${PREFERRED_DIRECTORY}/shared_dir *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo systemctl restart nfs-kernel-server

```

## 2. Mounting NFS share directory on Workers (worker)

```bash
sudo apt install nfs-common

mkdir -p ${PREFERRED_DIRECTORY}/shared_dir

sudo mount ${CONTROLLER_NAME}${PREFERRED_DIRECTORY}/shared_dir ${PREFERRED_DIRECTORY}/shared_dir/

echo "slurm-master-node-01:${PREFERRED_DIRECTORY}/shared_dir ${PREFERRED_DIRECTORY}/shared_dir nfs defaults 0 0" | sudo tee -a /etc/fstab
```

# Setting up OpenMPI

## Installing openmpi (all)

```bash
sudo apt update
sudo apt install openmpi-bin openmpi-common libopenmpi-dev

# Verify Version
which mpicc
mpicc --version
```
