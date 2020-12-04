#! /bin/sh

BUILD_KERNEL=${BUILD_KERNEL:-"true"};
KERNEL_VERSION=${KERNEL_VERSION:-"5.9.6"}
LLVM_VERSION=${LLVM_VERSION:-9}

DOCKER_BUILD_DIR=/tmp/docker_build
DOCKER_DAEMON_JSON=/etc/docker/daemon.json
WORK_DIR=`pwd`

install_package_if_necessary() {
    if [ -z "$1" ]; then
        echo "Please input package name"
    elif [ -z `dpkg --list | grep $1` ]; then
        echo "Install package $1"
        sudo -E apt-get --yes install $1
    else
        echo "$1 already installed"
    fi
}

set_default_llvm_tool() {
    if [ -z "$1" ]; then
        echo "Please input LLVM tool name"
    elif [ -x "`command -v $1-$LLVM_VERSION`" ]; then
        TOOL_PATH=`command -v $1-$LLVM_VERSION`
        TOOL_DIR=`dirname $TOOL_PATH`
        sudo -E cp --force --symbolic-link $TOOL_PATH $TOOL_DIR/$1
        ls -lsh `which $1`
    else
        echo "LLVM tool $1-$LLVM_VERSION not found"
        /bin/false
    fi
}

# Remove clang path from PATH env when run inTravis-CI
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
if [ ! -x "`command -v docker`" ]; then
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
install_package_if_necessary kata-proxy
install_package_if_necessary kata-runtime
install_package_if_necessary kata-shim

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

    # Install Clang and LLVM
    install_package_if_necessary clang-$LLVM_VERSION
    install_package_if_necessary lld-$LLVM_VERSION
    install_package_if_necessary llvm-$LLVM_VERSION-dev

    # Install kernel build dependencies
    install_package_if_necessary libelf-dev
#    sudo -E apt-get --yes install \
#        bc \
#        bison \
#        build-essential \
#        clang-$LLVM_VERSION \
#        flex \
#        libncurses-dev \
#        libssl-dev \
#        libelf-dev \
#        lld-$LLVM_VERSION \
#        llvm-$LLVM_VERSION-dev \
#        ;
    # Use LLVM to compile kernel, according to
    # https://www.kernel.org/doc/html/latest/kbuild/llvm.html
    export LLVM=1
    export CC=clang
    export LD=ld.lld
    export AR=llvm-ar
    export NM=llvm-nm
    export STRIP=llvm-strip
    export OBJCOPY=llvm-objcopy
    export OBJDUMP=llvm-objdump
    export OBJSIZE=llvm-size
    export READELF=llvm-readelf
    export HOSTCC=clang
    export HOSTCXX=clang++
    export HOSTAR=llvm-ar
    export HOSTLD=ld.lld

    set_default_llvm_tool clang
    set_default_llvm_tool ld.lld
    set_default_llvm_tool llvm-ar
    set_default_llvm_tool llvm-nm
    set_default_llvm_tool llvm-strip
    set_default_llvm_tool llvm-objcopy
    set_default_llvm_tool llvm-objdump
    set_default_llvm_tool llvm-size
    set_default_llvm_tool llvm-readelf
    set_default_llvm_tool clang++

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
    #    libclang-$LLVM_VERSION-dev \
    #    libedit-dev \
    #    libelf-dev \
    #    libfl-dev \
    #    libncurses-dev \
    #    libssl-dev \
    #    libz-dev \
    #    lld \
    #    llvm-$LLVM_VERSION-dev \
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
    if [ -e "/dev/kvm" ]; then
        docker run \
                -it \
                --rm \
                --runtime=kata-runtime \
                ubuntu uname -r \
            | grep $KERNEL_VERSION \
            || (echo "Failed to load new kernel $KERNEL_VERSION in Kata" && false)
    fi
fi
