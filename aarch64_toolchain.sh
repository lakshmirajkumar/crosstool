#! /bin/bash
set -e
set -x

TOPDIR=${PWD}
SRCDIR=$TOPDIR/sources
BLDDIR=$TOPDIR/build
DEBDIR=$TOPDIR/deb
INSTALL_PATH=$TOPDIR/install
TARGET=aarch64-linux-gnu
USE_NEWLIB=0
LINUX_ARCH=arm64
CONFIGURATION_OPTIONS="--disable-multilib" # --disable-threads --disable-shared
PARALLEL_MAKE=-j4
BINUTILS_VERSION=binutils-2.25.1
GCC_VERSION=gcc-4.9.2
LINUX_KERNEL_VERSION=linux-3.17.2
GLIBC_VERSION=glibc-2.20
MPFR_VERSION=mpfr-3.1.2
GMP_VERSION=gmp-6.0.0a
MPC_VERSION=mpc-1.0.2
ISL_VERSION=isl-0.12.2
CLOOG_VERSION=cloog-0.18.1
export PATH=$INSTALL_PATH/bin:$PATH

rm -rf $SRCDIR;mkdir -p $SRCDIR
rm -rf $BLDDIR;mkdir -p $BLDDIR
rm -rf $DEBDIR;mkdir -p $DEBDIR

function create_deb {
	cd $INSTALL_PATH
	mkdir debian;mkdir -p debian/control
	find * -type f | sort | xargs md5sum > debian/control/md5sums
	tar c -z --owner=root --group=root -f $DEBDIR/data.tar.gz ./
	
	cd debian/control;
	SIZE=`du -s $INSTALL_PATH | cut -f1`
	VER=`cat $1 |cut -d "-" -f 2`
	cat > control << EOF
Package: $1
Source: $1
Version: $VER
Installed-Size: $SIZE
Maintainer: Andre Przywara <osp@andrep.de>
Architecture: LINUX_ARCH
Section: devel
Priority: extra
EOF
	tar c -z --owner=root --group=root -f $DEBDIR/control.tar.gz ./
	echo "2.0" > $DEBDIR/debian-binary
	cd ../
	ar q $DEBDIR/$1-${TARGET}.deb $DEBDIR/debian-binary $DEBDIR/control.tar.gz $DEBDIR/data.tar.gz
	rm -rf $DEBDIR/control.tar.gz $DEBDIR/data.tar.gz $DEBDIR/debian-binary
	rm -rf $INSTALL_PATH/debian
}

# Download packages
cd $SRCDIR
wget -nc https://ftp.gnu.org/gnu/binutils/$BINUTILS_VERSION.tar.gz
wget -nc https://ftp.gnu.org/gnu/gcc/$GCC_VERSION/$GCC_VERSION.tar.gz
if [ $USE_NEWLIB -ne 0 ]; then
    wget -nc -O newlib-master.zip https://github.com/bminor/newlib/archive/master.zip || true
    unzip -qo newlib-master.zip
else
    wget -nc https://www.kernel.org/pub/linux/kernel/v3.x/$LINUX_KERNEL_VERSION.tar.xz
    wget -nc https://ftp.gnu.org/gnu/glibc/$GLIBC_VERSION.tar.xz
fi
wget -nc https://ftp.gnu.org/gnu/mpfr/$MPFR_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/gmp/$GMP_VERSION.tar.xz
wget -nc https://ftp.gnu.org/gnu/mpc/$MPC_VERSION.tar.gz
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/$ISL_VERSION.tar.bz2
wget -nc ftp://gcc.gnu.org/pub/gcc/infrastructure/$CLOOG_VERSION.tar.gz
# Extract everything
for f in *.tar*; do tar xfk $f; done
cd $TOPDIR

# Make symbolic links
cd $SRCDIR/$GCC_VERSION
ln -sf `ls -1d ../mpfr-*/` mpfr
ln -sf `ls -1d ../gmp-*/` gmp
ln -sf `ls -1d ../mpc-*/` mpc
ln -sf `ls -1d ../isl-*/` isl
ln -sf `ls -1d ../cloog-*/` cloog
cd $TOPDIR

# Step 1. Binutils
mkdir -p $BLDDIR/build-binutils
rm -rf $INSTALL_PATH;mkdir -p $INSTALL_PATH
cd $BLDDIR/build-binutils
$SRCDIR/$BINUTILS_VERSION/configure --prefix=$INSTALL_PATH --target=$TARGET $CONFIGURATION_OPTIONS
make $PARALLEL_MAKE
make install
create_deb $BINUTILS_VERSION
cd $TOPDIR

# Step 3. C/C++ Compilers
mkdir -p $BLDDIR/build-gcc
#rm -rf $INSTALL_PATH;mkdir -p $INSTALL_PATH
cd $BLDDIR/build-gcc
if [ $USE_NEWLIB -ne 0 ]; then
	NEWLIB_OPTION=--with-newlib 
fi
$SRCDIR/$GCC_VERSION/configure --prefix=$INSTALL_PATH --target=$TARGET --enable-languages=c,c++ $CONFIGURATION_OPTIONS $NEWLIB_OPTION
make $PARALLEL_MAKE all-gcc
make install-gcc
create_deb $GCC_VERSION
cd $TOPDIR

if [ $USE_NEWLIB -ne 0 ]; then
    # Steps 4-6: Newlib
    mkdir -p $BLDDIR/build-newlib
    #rm -rf $INSTALL_PATH;mkdir -p $INSTALL_PATH
    cd $BLDDIR/build-newlib
    $SRCDIR/newlib-master/configure --prefix=$INSTALL_PATH --target=$TARGET $CONFIGURATION_OPTIONS
    make $PARALLEL_MAKE
    make install
    create_deb "newlib" 
    cd $TOPDIR
else
    # Step 2. Linux Kernel Headers
    #rm -rf $INSTALL_PATH;mkdir -p $INSTALL_PATH 
    cd $SRCDIR/$LINUX_KERNEL_VERSION
    make ARCH=$LINUX_ARCH INSTALL_HDR_PATH=$INSTALL_PATH/$TARGET headers_install
    cd $TOPDIR
    # Step 4. Standard C Library Headers and Startup Files
    mkdir -p $BLDDIR/build-glibc
    cd $BLDDIR/build-glibc
    $SRCDIR/$GLIBC_VERSION/configure --prefix=$INSTALL_PATH/$TARGET --host=$TARGET --target=$TARGET --with-headers=$INSTALL_PATH/$TARGET/include $CONFIGURATION_OPTIONS libc_cv_forced_unwind=yes
    make install-bootstrap-headers=yes install-headers
    make $PARALLEL_MAKE csu/subdir_lib
    install csu/crt1.o csu/crti.o csu/crtn.o $INSTALL_PATH/$TARGET/lib
    $TARGET-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $INSTALL_PATH/$TARGET/lib/libc.so
    touch $INSTALL_PATH/$TARGET/include/gnu/stubs.h
    cd $TOPDIR

    # Step 5. Compiler Support Library
    cd $BLDDIR/build-gcc
    make $PARALLEL_MAKE all-target-libgcc
    make install-target-libgcc
    cd $TOPDIR

   # Step 6. Standard C Library & the rest of Glibc
    cd $BLDDIR/build-glibc
    make $PARALLEL_MAKE
    make install
    cd $TOPDIR
fi

# Step 7. Standard C++ Library & the rest of GCC
cd $BLDDIR/build-gcc
make $PARALLEL_MAKE all
make install
cd $TOPDIR
create_deb $GLIBC_VERSION 

echo 'Success!'
