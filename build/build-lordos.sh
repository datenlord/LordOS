#! /bin/sh

# Documents
# https://gist.github.com/chrisdone/02e165a0004be33734ac2334f215380e
# https://gist.github.com/pwang7/7e72772bf3729db06efd8f450a83a8c6

set -o errexit
set -o nounset
set -o xtrace

sudo apt-get update

export LORDOS_VERSION=lordos-0.1
export ARCH=${ARCH:-"x86_64"}
case $ARCH in
    "aarch64")
        export TARGET_TRIPLET=aarch64-unknown-linux-gnu
        export KERNEL_CONFIG_FILE=aarch64-kernel.config
        export BUILDROOT_CONFIG_FILE=buildroot-aarch64.def.config
        export PREBUILD_TOOLCHAIN_URL="https://github.com/datenlord/data-sync/releases/download/2020.12.07-aarch64/aarch64-unknown-linux-gnu.tgz"
        sudo apt-get --yes install qemu-system-arm
        ;;
    "arm")
        export TARGET_TRIPLET=arm-unknown-linux-gnueabi
        export KERNEL_CONFIG_FILE=arm-kernel.config
        export BUILDROOT_CONFIG_FILE=buildroot-arm.def.config
        export PREBUILD_TOOLCHAIN_URL="https://github.com/datenlord/data-sync/releases/download/2020.12.07-arm/arm-unknown-linux-gnueabi.tgz"
        sudo apt-get --yes install qemu-system-arm
        ;;
    "x86_64")
        export TARGET_TRIPLET=x86_64-unknown-linux-gnu
        export KERNEL_CONFIG_FILE=x86_64-kernel.config
        export BUILDROOT_CONFIG_FILE=buildroot-x86_64.def.config
        export PREBUILD_TOOLCHAIN_URL="https://github.com/datenlord/data-sync/releases/download/2020.12.07-x86_64/x86_64-unknown-linux-gnu.tgz"
        sudo apt-get --yes install qemu-system-x86
        ;;
esac
echo "target: $TARGET_TRIPLET"

export CODE=`pwd`/code
mkdir -p $CODE
export BUILDS=`pwd`/lordos_builds
mkdir -p $BUILDS
cp build/*.config $BUILDS
cp build/init $BUILDS
# sed "s/CONFIG_LOCALVERSION=\"\"/CONFIG_LOCALVERSION=\"$LORDOS_VERSION\"/g" build/$KERNEL_CONFIG_FILE > $BUILDS/$KERNEL_CONFIG_FILE
# diff build/$KERNEL_CONFIG_FILE $BUILDS/$KERNEL_CONFIG_FILE | grep $LORDOS_VERSION

qemu-system-$ARCH --machine help

# prebuild x-tools
export TOOLCHAIN_BASE_DIR=$HOME/x-tools
mkdir -p $TOOLCHAIN_BASE_DIR
cd $TOOLCHAIN_BASE_DIR
wget --timestamping $PREBUILD_TOOLCHAIN_URL
if [ ! -d "$TARGET_TRIPLET" ]; then
    tar zxf $TARGET_TRIPLET.tgz
fi

# crosstool-ng
cd $CODE
export CROSSTOOL_CODE=$CODE/crosstool-ng
rm -rf $CROSSTOOL_CODE || echo "no need to remove $CROSSTOOL_CODE"
git clone http://github.com/crosstool-ng/crosstool-ng
if [ -x "`command -v ct-ng`" ]; then
    echo "no need to build ct-ng"
else
    # Dependencies already installed on GitHub action
    # sudo apt-get --yes install build-essential autoconf bison flex libncurses-dev texinfo unzip python-dev
    # Dependencies of crosstool-ng
    sudo apt-get --yes install help2man libtool-bin libtool-doc
    cd $CROSSTOOL_CODE
    ./bootstrap
    ./configure
    make
    sudo make install
fi
ct-ng show-$TARGET_TRIPLET

# build crosstool-ng toolchain
export TOOLCHAIN_DIR=$HOME/x-tools/$TARGET_TRIPLET
export PATH="$PATH:$TOOLCHAIN_DIR/bin"
export SYSROOT=$TOOLCHAIN_DIR/$TARGET_TRIPLET/sysroot
export GCC=$TARGET_TRIPLET-gcc
if [ -x "`command -v $GCC`" ]; then
    $GCC --version
    echo "no need to build toolchain"
else
    export CROSSTOOL_BUILD=$BUILDS/crosstool-ng
    rm -rf $CROSSTOOL_BUILD || echo "no need to remove $CROSSTOOL_BUILD"
    mkdir -p $CROSSTOOL_BUILD
    cd $CROSSTOOL_BUILD
    ct-ng $TARGET_TRIPLET
    # ct-ng x86_64-unknown-linux-gnu
    # mv ../crosstool-ng.config .config
    ct-ng build
fi

# test crosstool-ng toolchain
export CROSSTOOL_TEST=$BUILDS/crosstool-ng-test
rm -rf $CROSSTOOL_TEST || echo "no need to remove $CROSSTOOL_TEST"
mkdir -p $CROSSTOOL_TEST
cd $CROSSTOOL_TEST
export QEMU_TEST=qemu_test
cat <<EOF > $QEMU_TEST.c
#include <stdio.h>
int main(int argc, char*argv[])
{
    printf("Genuinely generated by the toolchain\n");
}
EOF
$GCC $QEMU_TEST.c -o $QEMU_TEST
chmod +x $QEMU_TEST
readelf -d $QEMU_TEST
readelf -l $QEMU_TEST
# qemu-$ARCH -L $SYSROOT $QEMU_TEST
rm $QEMU_TEST
$GCC -static $QEMU_TEST.c -o $QEMU_TEST
# qemu-$ARCH $QEMU_TEST

# kernel
export KERNEL_VERSION=`ct-ng show-$TARGET_TRIPLET | grep ': linux-' | cut -d '-' -f 2`
echo "kernel version: $KERNEL_VERSION"
export KERNEL_MAJOR_VERSION=`echo $KERNEL_VERSION | cut -d '.' -f 1`
export KERNEL_MINOR_VERSION=`echo $KERNEL_VERSION | cut -d '.' -f 2`
export LINUX_BUILD=$BUILDS/linux-$KERNEL_VERSION
rm -rf $LINUX_BUILD || echo "no need to remove $LINUX_BUILD"
mkdir -p $LINUX_BUILD
# cd $LINUX_BUILD
# mv ../$KERNEL_CONFIG_FILE defconfig
cd $CODE
export LINUX_CODE=$CODE/linux-$KERNEL_VERSION
wget --timestamping https://cdn.kernel.org/pub/linux/kernel/v$KERNEL_MAJOR_VERSION.x/linux-$KERNEL_VERSION.tar.xz
rm -rf $LINUX_CODE || echo "no need to remove $LINUX_CODE"
tar xf linux-$KERNEL_VERSION.tar.xz
# cd $CODE
# sudo ln -sf linux-$KERNEL_VERSION linux
cd $LINUX_CODE
# make O=$LINUX_BUILD ARCH=$ARCH CROSS_COMPILE="$TARGET_TRIPLET-" defconfig
make O=$LINUX_BUILD ARCH=$ARCH allnoconfig
cd $LINUX_BUILD
mv ../$KERNEL_CONFIG_FILE local.config
sed "s/CONFIG_LOCALVERSION=\"\"/CONFIG_LOCALVERSION=\"$LORDOS_VERSION\"/g" local.config > .config
diff local.config .config | grep $LORDOS_VERSION
time make ARCH=$ARCH CROSS_COMPILE="$TARGET_TRIPLET-" -j2

# busybox
cd $CODE
export BUSYBOX_CODE=$CODE/busybox
rm -rf $BUSYBOX_CODE || echo "no need to remove $BUSYBOX_CODE"
git clone git://busybox.net/busybox.git
export BUSYBOX_BUILD=$BUILDS/busybox
rm -rf $BUSYBOX_BUILD || echo "no need to remove $BUSYBOX_BUILD"
mkdir -p $BUSYBOX_BUILD
cd $BUSYBOX_CODE
make O=$BUSYBOX_BUILD defconfig
cd $BUSYBOX_BUILD
# make menuconfig
mv ../busybox.config .config
time make ARCH=$ARCH CROSS_COMPILE="$TARGET_TRIPLET-" -j2
make install

# initramfs
export INITRAMFS_BUILD=$BUILDS/initramfs
rm -rf $INITRAMFS_BUILD || echo "no need to remove $INITRAMFS_BUILD"
mkdir -p $INITRAMFS_BUILD
cd $INITRAMFS_BUILD
mkdir -p bin sbin etc proc sys usr/bin usr/sbin
cp -a $BUSYBOX_BUILD/_install/* .
cp ../init .
find . -print0 | cpio --null -ov --format=newc \
  | gzip -9 > $INITRAMFS_BUILD/initramfs.cpio.gz

# test run
timeout 15 qemu-system-$ARCH -kernel $LINUX_BUILD/arch/x86/boot/bzImage \
  -initrd $INITRAMFS_BUILD/initramfs.cpio.gz -nographic \
  -append "console=ttyS0" \
  || echo "mini_linux OK"

# buildroot
export BUILDROOT_BUILD=$BUILDS/buildroot
rm -rf $BUILDROOT_BUILD || echo "no need to remove $BUILDROOT_BUILD"
mkdir -p $BUILDROOT_BUILD
cd $BUILDROOT_BUILD
touch Config.in external.mk
echo 'name: LordOS' > external.desc
echo 'desc: LordOS Linux system with buildroot' >> external.desc
mkdir configs overlay
# make defconfig BR2_DEFCONFIG=$BUILDS/$BUILDROOT_CONFIG_FILE
# make menuconfig
# mv ../buildroot.config .config
cp ../init overlay/init
cd $CODE
export BUILDROOT_CODE=$CODE/buildroot
rm -rf $BUILDROOT_CODE || echo "no need to remove $BUILDROOT_CODE"
git clone https://github.com/buildroot/buildroot
cd $BUILDROOT_CODE
BUILDROOT_TAG=`git tag | grep -v rc | grep -v legacy | tail -n 1`
echo "buildroot release $BUILDROOT_TAG"
git checkout tags/$BUILDROOT_TAG
make O=$BUILDROOT_BUILD BR2_EXTERNAL=$BUILDROOT_BUILD defconfig BR2_DEFCONFIG=$BUILDS/$BUILDROOT_CONFIG_FILE
# make O=$BUILDROOT_BUILD BR2_EXTERNAL=$BUILDROOT_BUILD qemu_x86_64_defconfig
cd $BUILDROOT_BUILD
time make

timeout 20 qemu-system-$ARCH -kernel $LINUX_BUILD/arch/x86/boot/bzImage \
  -initrd $BUILDROOT_BUILD/images/rootfs.cpio.gz -nographic \
  -append "console=ttyS0" \
  || echo "mini_linux OK"