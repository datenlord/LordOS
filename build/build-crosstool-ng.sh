#! /bin/sh

export OPT=/opt
export BUILDS=/tmp/mini_linux_builds
mkdir -p $BUILDS

sudo apt-get update


# crosstool-ng
cd $BUILDS
git clone http://github.com/crosstool-ng/crosstool-ng
export CROSSTOOL_BUILD=$BUILDS/crosstool-ng
# Dependencies already installed on GitHub action
# sudo apt-get install build-essential autoconf bison flex libncurses-dev texinfo unzip python-dev
# Dependencies of crosstool-ng
sudo apt-get install help2man libtool-bin libtool-doc
cd $CROSSTOOL_BUILD
./bootstrap
./configure
make
sudo make install
ct-ng x86_64-unknown-linux-gnu
ct-ng build

