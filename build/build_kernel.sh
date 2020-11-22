#! /bin/sh

#ADD_CARGO_REPO_MIRROR=${ADD_CARGO_REPO_MIRROR:-"false"}
#BCC=${BCC:-"0.17.0"}
#BUILD_BCC=${BUILD_BCC:-"true"}
#BUILD_DOCKER_IMAGE=${BUILD_DOCKER_IMAGE:-"true"}
BUILD_KERNEL=${BUILD_KERNEL:-"true"};
#BUILD_BCC_INSIDE_KATA=${BUILD_BCC_INSIDE_KATA:-false}
#DIST=${DIST:-"bionic"}
#FEATURES=${FEATURES:-"v0_17_0"}
KERNEL_VERSION=${KERNEL_VERSION:-"5.9.6"}
LLVM=${LLVM:-9}
#STATIC=${STATIC:-"true"}
#RUST_BCC_DOCKER_NAME=rust-bcc-test-env
#RUST_BCC_DOCKER_NAME=${RUST_BCC_DOCKER_NAME:-"datenlord/rust_bcc:ubuntu20.04-bcc0.17.0"}

DOCKER_BUILD_DIR=/tmp/docker_build
DOCKER_DAEMON_JSON=/etc/docker/daemon.json
WORK_DIR=`pwd`

# Remove clang path from PATH env
TMPPATH=$(
for onepath in `echo $PATH | sed 's/:/\ /g'`; do
    echo $onepath | grep -v clang
done
)
export PATH=`echo $TMPPATH | sed 's/\\s\+/:/g'`
echo $PATH
echo $PATH | grep -c clang

set -o errexit
set -o nounset
set -o xtrace

# Configure Kata repo
ARCH=`arch`
KATA_BRANCH=master
echo "deb http://download.opensuse.org/repositories/home:/katacontainers:/releases:/${ARCH}:/${KATA_BRANCH}/xUbuntu_$(lsb_release -rs)/ /" \
    | sudo tee /etc/apt/sources.list.d/kata-containers.list
curl -sL  http://download.opensuse.org/repositories/home:/katacontainers:/releases:/${ARCH}:/${KATA_BRANCH}/xUbuntu_$(lsb_release -rs)/Release.key \
    | sudo apt-key add -
sudo apt-get update

# Install Docker if necessary
if ! [ -x `command -v docker` ]; then
    sudo apt-get --yes install docker.io
else
    echo "docker is already installed"
    docker version
    if [ -f $DOCKER_DAEMON_JSON ]; then
        cat $DOCKER_DAEMON_JSON
    else
        echo "$DOCKER_DAEMON_JSON not exist"
    fi
fi

# Install Kata components
sudo apt-get --yes install \
    kata-proxy \
    kata-runtime \
    kata-shim \
    ;
# Config Docker to use Kata runtime
sudo mkdir -p /etc/docker
sudo tee $DOCKER_DAEMON_JSON <<EOF
{
  "runtimes": {
    "kata-runtime": {
      "path": "/usr/bin/kata-runtime"
    }
  }
}
EOF

# Restart Docker with new OCI driver
sudo systemctl daemon-reload
sudo systemctl restart docker

if [ $BUILD_KERNEL = "true" ]; then
    export GOPATH=$WORK_DIR/go # Used when build kernel for Kata

    # Install kernel build dependencies
    sudo -E apt-get --yes install clang-$LLVM lld-$LLVM
    # Make installed clang and ld.lld as default
    sudo -E mv /usr/bin/clang-$LLVM /usr/bin/clang || which clang 
    sudo -E mv /usr/bin/ld.lld-$LLVM /usr/bin/ld.lld || which ld.lld
    # scripts/kconfig/conf  --syncconfig Kconfig

    #sudo apt-get --yes install \
    #    bc \
    #    exuberant-ctags \
    #    gcc \
    #    git \
    #    libncurses-dev \
    #    libssl-dev \
    #    make \
    #    ;
    #sudo apt-get --yes install \
    #    autoconf \
    #    bison \
    #    dkms \
    #    flex \
    #    libncurses-dev \
    #    libssl-dev \
    #    libelf-dev \
    #    libudev-dev \
    #    libpci-dev \
    #    libiberty-dev \
    #    openssl \
    #    ;

    # Install dependencies to build BCC and kernel
    #sudo apt-get --yes install \
    #    bison \
    #    build-essential \
    #    clang \
    #    cmake \
    #    flex \
    #    git \
    #    libclang-$LLVM-dev \
    #    libedit-dev \
    #    libelf-dev \
    #    libfl-dev \
    #    libncurses-dev \
    #    libssl-dev \
    #    libz-dev \
    #    lld \
    #    llvm-$LLVM-dev \
    #    llvm-$LLVM-dev \
    #    python \
    #    ;

    # Clone Kata packaging code to build kernel
    KATA_DIR=$GOPATH/src/github.com/kata-containers
    mkdir -p $KATA_DIR
    cd $KATA_DIR
    [ ! -d $KATA_DIR/packaging ] && git clone --depth 1 https://github.com/kata-containers/packaging
    cd packaging/kernel
    # Add following kernel config flag to whitelist, since it's not supported in new kernel
    echo CONFIG_MEMCG_SWAP_ENABLED >> configs/fragments/whitelist.conf
    # Build new kernel
    ./build-kernel.sh -v $KERNEL_VERSION -f -b -d setup
    ./build-kernel.sh -v $KERNEL_VERSION -d build
    # Install new kernel for kata-container, target install path is $DESTDIR/$PREFIX
    sudo -E ./build-kernel.sh -v $KERNEL_VERSION -d install

    # Verify the new kernel installed for kata-container
    docker run \
            -it \
            --rm \
            --runtime=kata-runtime \
            ubuntu uname -r \
        | grep $KERNEL_VERSION \
        || (echo "Failed to load new kernel $KERNEL_VERSION in Kata" && false)
fi
