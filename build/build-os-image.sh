#! /bin/sh

set -o errexit
set -o nounset
set -o xtrace

# Install golang
if ! [ -x `command -v go` ]; then
    wget https://golang.org/dl/go1.15.5.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go*.tar.gz
    export PATH=$PATH:/usr/local/go/bin
fi

export GOPATH=/tmp/go
export ROOTFS_DIR=/tmp/rootfs-bionic/

if [ -d $GOPATH ]; then
    sudo rm -rf $GOPATH
fi

if [ -d $ROOTFS_DIR ]; then
    sudo rm -rf $ROOTFS_DIR
fi

# Install dependencies
sudo apt-get update && sudo apt-get --yes install
    build-essential \
    debootstrap \
    qemu-utils \
    ;

# Download kata-containers/osbuilder
KATA_DIR=$GOPATH/src/github.com/kata-containers
mkdir -p $KATA_DIR
cd $KATA_DIR
git clone https://github.com/kata-containers/osbuilder

cd $KATA_DIR/osbuilder/rootfs-builder
sudo -E PATH=$PATH  GOPATH=$GOPATH AGENT_INIT=yes EXTRA_PKGS="vim emacs" ./rootfs.sh -r $ROOTFS_DIR ubuntu

cd ../initrd-builder/
sudo -E AGENT_INIT=yes ./initrd_builder.sh ${ROOTFS_DIR}

cd ../image-builder/
sudo -E ./image_builder.sh ${ROOTFS_DIR}
