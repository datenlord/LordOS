#! /bin/sh

# Documents
# https://gist.github.com/pwang7/7e72772bf3729db06efd8f450a83a8c6

set -o errexit
set -o nounset
set -o xtrace

export OPT=/opt
export BUILDS=/tmp/mini_linux_builds
mkdir -p $BUILDS
cp build/*.config $BUILDS
cp build/init $BUILDS

sudo apt-get update
sudo apt-get --yes install qemu

# crosstool-ng
cd $BUILDS
git clone http://github.com/crosstool-ng/crosstool-ng
export CROSSTOOL_BUILD=$BUILDS/crosstool-ng
# Dependencies already installed on GitHub action
# sudo apt-get --yes install build-essential autoconf bison flex libncurses-dev texinfo unzip python-dev
# Dependencies of crosstool-ng
sudo apt-get --yes install help2man libtool-bin libtool-doc
cd $CROSSTOOL_BUILD
./bootstrap
./configure
make
sudo make install
# ct-ng x86_64-unknown-linux-gnu
mv ../crosstool-ng.config .config
ct-ng build

# kernel
cd $BUILDS
export KERNEL_VERSION=5.8.9
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$KERNEL_VERSION.tar.xz
tar xf linux-$KERNEL_VERSION.tar.xz
sudo mv linux-$KERNEL_VERSION $OPT
cd $OPT
sudo ln -sf linux-$KERNEL_VERSION linux
export LINUX=$OPT/linux
export LINUX_BUILD=$BUILDS/linux
mkdir -p $LINUX_BUILD
cd $LINUX
make O=$LINUX_BUILD allnoconfig
cd $LINUX_BUILD
# make menuconfig
mv ../mini_kernel.config .config
time make -j2

# busybox
cd $BUILDS
git clone git://busybox.net/busybox.git
sudo mv busybox $OPT
export BUSYBOX=$OPT/busybox
export BUSYBOX_BUILD=$BUILDS/busybox
mkdir -p $BUSYBOX_BUILD
cd $BUSYBOX
make O=$BUSYBOX_BUILD defconfig
cd $BUSYBOX_BUILD
# make menuconfig
mv ../busybox.config .config
time make -j2
make install

# initramfs
export INITRAMFS_BUILD=$BUILDS/initramfs
mkdir -p $INITRAMFS_BUILD
cd $INITRAMFS_BUILD
mkdir -p bin sbin etc proc sys usr/bin usr/sbin
cp -a $BUSYBOX_BUILD/_install/* .
cp ../init .
find . -print0 | cpio --null -ov --format=newc \
  | gzip -9 > $INITRAMFS_BUILD/initramfs.cpio.gz

# test run
timeout 15 qemu-system-x86_64 -kernel $LINUX_BUILD/arch/x86/boot/bzImage \
  -initrd $INITRAMFS_BUILD/initramfs.cpio.gz -nographic \
  -append "console=ttyS0" \
  || echo "mini_linux OK"

# buildroot
cd $BUILDS
git clone https://github.com/buildroot/buildroot
sudo mv buildroot $OPT
export BUILDROOT=$OPT/buildroot
export BUILDROOT_BUILD=$BUILDS/buildroot
mkdir -p $BUILDROOT_BUILD
cd $BUILDROOT_BUILD
touch Config.in external.mk
echo 'name: mini_linux' > external.desc
echo 'desc: minimal linux system with buildroot' >> external.desc
mkdir configs overlay
cd $BUILDROOT
make O=$BUILDROOT_BUILD BR2_EXTERNAL=$BUILDROOT_BUILD qemu_x86_64_defconfig
cd $BUILDROOT_BUILD
# make menuconfig
cp ../init overlay/init
mv ../buildroot.config .config
time make

timeout 20 qemu-system-x86_64 -kernel $LINUX_BUILD/arch/x86/boot/bzImage \
  -initrd $BUILDROOT_BUILD/images/rootfs.cpio.gz -nographic \
  -append "console=ttyS0" \
  || echo "mini_linux OK"
