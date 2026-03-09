
# Installing Podman 5.8.0 on Ubuntu 22.04

Use the following commands to build podman from source

```bash

sudo apt-get update
sudo apt-get install -y btrfs-progs gcc git \
  iptables libassuan-dev libbtrfs-dev libc6-dev libdevmapper-dev \
  libglib2.0-dev libgpgme-dev libgpg-error-dev libprotobuf-dev \
  libprotobuf-c-dev libseccomp-dev libselinux1-dev libsystemd-dev \
  make pkg-config runc uidmap containernetworking-plugins

# Download Go 1.24.2
cd ~
wget https://go.dev/dl/go1.24.2.linux-amd64.tar.gz

# Extract to /usr/local
sudo tar -C /usr/local -xzf go1.24.2.linux-amd64.tar.gz

# Clean up
rm go1.24.2.linux-amd64.tar.gz

# Add to your current session
export PATH=/usr/local/go/bin:$PATH

# Make it permanent
echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Check go version
go version

# Install podman  
cd ~

git clone --branch v5.8.0 https://github.com/containers/podman.git
cd podman
make BUILDTAGS="selinux seccomp"
sudo make install

# Install conmon
sudo apt-get install -y make git gcc pkg-config libglib2.0-dev libseccomp-dev libsystemd-dev libbsd-dev

cd ~
git clone https://github.com/containers/conmon.git
cd conmon
make
sudo make podman

# Install rust
cd ~
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# Press 1 for default install

# Load Rust into current session
source "$HOME/.cargo/env"

# Verify
rustc --version

# Install dependancy
sudo apt-get install -y make git protobuf-compiler libsystemd-dev libseccomp-dev clang

# Install netavark
cd ~
git clone https://github.com/containers/netavark.git
cd netavark
make

sudo mkdir -p /usr/libexec/podman
sudo install -m 755 bin/netavark /usr/libexec/podman/netavark
# Install netavark dns
cd ~
git clone https://github.com/containers/aardvark-dns.git
cd aardvark-dns
make
sudo install -m 755 bin/aardvark-dns /usr/libexec/podman/aardvark-dns

/usr/libexec/podman/netavark --version
/usr/libexec/podman/aardvark-dns --version

# Install passt
sudo apt-get install -y make git gcc pkg-config libcap-dev libseccomp-dev linux-headers-$(uname -r)

sudo apt-get install -y slirp4netns
cd ~
git clone https://passt.top/passt
cd passt
make

sudo install -m 755 pasta /usr/local/bin/pasta
sudo install -m 755 passt /usr/local/bin/passt

# Check version
pasta --version

# Finally verify if podman is able to detect images
podman image ls

```
