#!/bin/bash

## To build a cross-compiler for linux targets we:
# 1) Download kernel headers
# 2) Install binutils
# 3) Install a C compiler
# 4) Get glibc headers
# 5) Install libgcc
# 6) Install the rest of glibc
# 7) Build a complete gcc/gfortran


# These steps are given by the following bash functions:
#   install_kernel_headers
#   install_binutils
#   install_gcc_stage1
#   install_glibc_stage1
#   install_gcc_stage2
#   install_glibc_stage2
#   install_gcc_stage3
#
# Ensure that you have set the following environment variables:
#   target
#   linux_version (defaults to 4.12)
#   binutils_version (defaults to 2.28)
#   gcc_version (defaults to 7.2.0)
#   glibc_version (defaults to 2.17)

## To build a cross-compile for OSX targets we:
# 1) Download OSX SDK
# 2) Install libtapi
# 3) Install cctools
# 4) Install dsymutil
# 5) Install gcc
## These steps are given by the following bash functions:
#   install_osx_sdk
#   install_libtapi
#   install_cctools
#   install_dsymutil
#   install_gcc
#
# Ensure that you have set the following environment variables:
#   target
#   libtapi_version (defaults to 1.30.0)
#   cctools_version (defaults to 22ebe727a5cdc21059d45313cf52b4882157f6f0)
#   dsymutil_version (defaults to 6fe249efadf6139a7f271fee87a5a0f44e2454cf)
#   gcc_version (defaults to 7.1.0)

# This is useful for debugging outside the container
system_root=${system_root:=}

# Set defaults of envvars
linux_version=${linux_version:-4.12}
binutils_version=${binutils_version:-2.29.1}
gcc_version=${gcc_version:-7.2.0}
glibc_version=${glibc_version:-2.17}

# osx defaults
libtapi_version=${libtapi_version:-1.30.0}
cctools_version=${cctools_version:-22ebe727a5cdc21059d45313cf52b4882157f6f0}
dsymutil_version=${dsymutil_version:-6fe249efadf6139a7f271fee87a5a0f44e2454cf}

# windows defaults
mingw_version=${mingw_version:-5.0.2}

# By default, execute `make` commands with N + 1 jobs, where N is the number of CPUs
nproc_cmd='nproc'
if type nproc 2> /dev/null ; then
    nproc_cmd='nproc'
else
    nproc_cmd="cat /proc/cpuinfo | grep 'processor' | wc -l"
fi
nproc=$(eval "$nproc_cmd")
if [[ $nproc > 8 ]]; then
    nproc=8
fi

## Function to take in a target such as `aarch64-linux-gnu`` and spit out a
## linux kernel arch like "arm64".
target_to_linux_arch()
{
    case "$1" in
        arm*)
            echo "arm"
            ;;
        aarch64*)
            echo "arm64"
            ;;
        powerpc*)
            echo "powerpc"
            ;;
        i686*)
            echo "x86"
            ;;
        x86*)
            echo "x86"
            ;;
    esac
}

## Function to take in a target such as `x86_64-apple-darwin14` and spit out
## an SDK version such as "10.10"
target_to_darwin_sdk()
{
    case "$1" in
        *darwin14*)
            echo "10.10"
            ;;
        *darwin15*)
            echo "10.11"
            ;;
        *darwin16*)
            echo "10.12"
            ;;
    esac
}


## Function to download and install Linux kernel headers
install_kernel_headers()
{
    linux_url=http://www.kernel.org/pub/linux/kernel/v4.x/linux-${linux_version}.tar.xz

    # Download and install linux headers
    cd $system_root/src
    download_unpack.sh "${linux_url}"
    cd $system_root/src/linux-${linux_version}
    local ARCH="$(target_to_linux_arch ${target})"
    ${L32} make ARCH=${ARCH} mrproper
    ${L32} make ARCH=${ARCH} headers_check
    sudo -E ${L32} make INSTALL_HDR_PATH=${system_root}/opt/${target}/${target}/sys-root/usr ARCH=${ARCH} V=0 headers_install

    # Cleanup
    cd $system_root/src
    sudo -E rm -rf linux-${linux_version}
}

download_gcc()
{
    # First argument is the version
    gcc_url=https://mirrors.kernel.org/gnu/gcc/gcc-${gcc_version}/gcc-${gcc_version}.tar.xz

    # Download and unpack gcc
    cd ${system_root}/src
    download_unpack.sh "${gcc_url}"
    cd ${system_root}/src/gcc-${gcc_version}

    # Build gcc (stage 1)
    ${L32} contrib/download_prerequisites
}

install_gcc_bootstrap()
{
    mkdir -p ${system_root}/src/gcc-${gcc_version}_bootstrap_build
    cd ${system_root}/src/gcc-${gcc_version}_bootstrap_build
    ${L32} ${system_root}/src/gcc-${gcc_version}/configure \
        --prefix=${system_root}/opt/${target} \
        --target=${target} \
        --host=${MACHTYPE} \
        --build=${MACHTYPE} \
        --disable-multilib \
        --disable-werror \
        --disable-shared \
        --disable-threads \
        --disable-libatomic \
        --disable-decimal-float \
        --disable-libffi \
        --disable-libgomp \
        --disable-libitm \
        --disable-libmpx \
        --disable-libquadmath \
        --disable-libssp \
        --disable-libsanitizer \
        --without-headers \
        --with-newlib \
        --disable-bootstrap \
        --with-glibc-version=$(echo $glibc_version | cut -d '.' -f 1-2) \
        --enable-languages=c \
        --with-sysroot=/opt/${target}/${target}/sys-root

    ${L32} make -j${nproc}
    sudo ${L32} make install

    # This is needed for any glibc older than 2.14, which includes the following commit
    # https://sourceware.org/git/?p=glibc.git;a=commit;h=95f5a9a866695da4e038aa4e6ccbbfd5d9cf63b7
    ln -vs libgcc.a `${target}-gcc -print-libgcc-file-name | \
    	sed 's/libgcc/&_eh/'`

}

install_glibc()
{
    # First argument is the version
    glibc_url="http://mirrors.peers.community/mirrors/gnu/glibc/glibc-${glibc_version}.tar.xz"
    cd ${system_root}/src
    download_unpack.sh "${glibc_url}"

    # patch glibc for ARM
    cd ${system_root}/src/glibc-${glibc_version}
    
    # patch glibc to keep around libgcc_s_resume on arm
    # ref: https://sourceware.org/ml/libc-alpha/2014-05/msg00573.html
    if [[ "${target}" == arm* ]] || [[ "${target}" == aarch* ]]; then 
        patch -p1 < ${system_root}/downloads/patches/glibc_arm_gcc_fix.patch
    fi

    # patch glibc's stupid gcc version check (we don't require this one, as if
    # it doesn't apply cleanly, it's probably fine)
    patch -p0 < ${system_root}/downloads/patches/glibc_gcc_version.patch || true

    # patch glibc's 32-bit assembly to withstand __i686 definition of newer GCC's
    # ref: http://comments.gmane.org/gmane.comp.lib.glibc.user/758
    if [[ "${target}" == i686* ]]; then
        patch -p1 < ${system_root}/downloads/patches/glibc_i686_asm.patch
    fi

    # Patch glibc's sunrpc cross generator to work with musl
    # See https://sourceware.org/bugzilla/show_bug.cgi?id=21604
    patch -p0 < $system_root/downloads/patches/glibc-sunrpc.patch

    # patch for building old glibc on newer binutils
    patch -p0 < $system_root/downloads/patches/glibc_nocommon.patch

    cd ${system_root}/src/glibc-${glibc_version}

    # build glibc
    mkdir -p ${system_root}/src/glibc-${glibc_version}_build
    cd ${system_root}/src/glibc-${glibc_version}_build
    ${L32} ${system_root}/src/glibc-${glibc_version}/configure \
        --prefix=/usr \
        --host=${target} \
        --with-headers=${system_root}/opt/${target}/${target}/sys-root/usr/include \
        --with-binutils=${system_root}/opt/${target}/bin \
        --enable-multilib \
        --disable-werror

    sudo -E chown $(id -u):$(id -g) -R ${system_root}/src/glibc-${glibc_version}_build
    ${L32} make -j${nproc}
    sudo -E ${L32} make install DESTDIR=/opt/${target}/${target}/sys-root

    # Cleanup
    cd ${system_root}/src
    sudo -E rm -rf glibc-${glibc_version}*
}

install_gcc()
{
    cd ${system_root}/src/gcc-${gcc_version}

    # target-specific GCC configuration flags
    GCC_CONF_ARGS=""

    # If we're building for Darwin, add on some extra configure arguments
    if [[ "${target}" == *apple* ]]; then
        sdk_version="$(target_to_darwin_sdk ${target})"
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --with-sysroot=${system_root}/opt/${target}/MacOSX${sdk_version}.sdk"
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --with-ld=${system_root}/opt/${target}/bin/${target}-ld"
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --with-as=${system_root}/opt/${target}/bin/${target}-as"
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --enable-languages=c,c++,fortran,objc,obj-c++"
    fi

    #patch -p1 < /downloads/patches/gcc_libmpx_limits.patch
    if [[ "${target}" == *linux* ]]; then
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --enable-languages=c,c++,fortran"
    fi

    # Build gcc (stage 1)
    mkdir -p ${system_root}/src/gcc-${gcc_version}_build
    cd ${system_root}/src/gcc-${gcc_version}_build
    ${L32} ${system_root}/src/gcc-${gcc_version}/configure \
        --prefix=${system_root}/opt/${target} \
        --target=${target} \
        --host=${MACHTYPE} \
        --build=${MACHTYPE} \
        --enable-threads=posix \
        --enable-host-shared \
        --disable-multilib \
        --disable-werror \
        --with-native-system-header-dir=${system_root}/opt/${target}/${target}/sys-root/usr/include \
        ${GCC_CONF_ARGS}

    ${L32} make -j${nproc}

    # Install gcc (stage 1)
    sudo -E ${L32} make install

    # Because this always writes out .texi files, we have to chown them back.  >:(
    sudo -E ${L32} chown $(id -u):$(id -g) -R .

    # Cleanup
    cd ${system_root}/src
    sudo -E rm -rf gcc-${gcc_version}*

    # Finally, create a bunch of symlinks stripping out the target so that
    # things like `gcc` "just work", as long as we've got our path set properly
    for f in ${system_root}/opt/${target}/bin/${target}-*; do
        fbase=$(basename $f)
        # We don't worry about failure to create these symlinks, as sometimes there are files
        # name ridiculous things like ${target}-${target}-foo, which screws this up
        sudo ln -s $f ${system_root}/opt/${target}/bin/${fbase#${target}-} || true
    done
}

# Helper to install a binutils cross-chain
install_binutils()
{
    # First argument is the version
    binutils_url=https://ftp.gnu.org/gnu/binutils/binutils-${binutils_version}.tar.bz2

    cd $system_root/src
    download_unpack.sh "${binutils_url}"

    # Build binutils!
    cd $system_root/src/binutils-${binutils_version}
    ${L32} ./configure \
        --prefix=/opt/${target} \
        --target=${target} \
        --disable-multilib \
        --disable-werror
    ${L32} make -j${nproc}

    # Install binutils
    sudo -E ${L32} make install

    # Cleanup
    cd $system_root/src
    sudo -E rm -rf binutils-${binutils_version}
}

## Helper to install stage1 of GCC (e.g. the C/C++ compilers, without libc)
install_gcc_stage1()
{
    # First argument is the version
    gcc_url=https://mirrors.kernel.org/gnu/gcc/gcc-${gcc_version}/gcc-${gcc_version}.tar.xz

    # Download and unpack gcc
    cd $system_root/src
    download_unpack.sh "${gcc_url}"
    cd $system_root/src/gcc-${gcc_version}

    # target-specific GCC configuration flags
    GCC_CONF_ARGS=""

    # If we're building for Darwin, add on some extra configure arguments
    if [[ "${target}" == *apple* ]]; then
        sdk_version="$(target_to_darwin_sdk ${target})"
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --with-sysroot=/opt/${target}/MacOSX${sdk_version}.sdk"
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --with-ld=/opt/${target}/bin/${target}-ld"
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --with-as=/opt/${target}/bin/${target}-as"
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --enable-languages=c,c++,fortran,objc,obj-c++"
    fi

    patch -p1 < $system_root/downloads/patches/gcc_libmpx_limits.patch
    if [[ "${target}" == *linux* ]]; then
        GCC_CONF_ARGS="${GCC_CONF_ARGS} --enable-languages=c,c++,fortran"
    fi

    # Build gcc (stage 1)
    ${L32} contrib/download_prerequisites
    mkdir -p $system_root/src/gcc-${gcc_version}_build
    cd $system_root/src/gcc-${gcc_version}_build
    ${L32} $system_root/src/gcc-${gcc_version}/configure \
        --prefix=/opt/${target} \
        --target=${target} \
        --host=${MACHTYPE} \
        --build=${MACHTYPE} \
        --enable-threads=posix \
        --enable-host-shared \
        --disable-multilib \
        --disable-werror \
        ${GCC_CONF_ARGS}

    ${L32} make -j${nproc} all-gcc

    # Install gcc (stage 1)
    sudo -E ${L32} make install-gcc

    # Because this always writes out .texi files, we have to chown them back.  >:(
    sudo -E ${L32} chown $(id -u):$(id -g) -R .
}


# Helper to install libgcc
install_gcc_stage2()
{
    # Install libgcc (stage 2)
    cd $system_root/src/gcc-${gcc_version}_build
    ${L32} make -j${nproc} all-target-libgcc
    sudo -E ${L32} make install-target-libgcc
}

# Helper to install the rest of GCC like gfortran, etc..., now that we've got
# an actual libc and compiler chain to compile with
install_gcc_stage3()
{
    # Install everything else like gfortran (stage 3)
    cd $system_root/src/gcc-${gcc_version}_build
    ${L32} make -j${nproc}
    sudo -E ${L32} make install

    # Cleanup
    cd $system_root/src
    sudo -E rm -rf gcc-${gcc_version}*

    # Finally, create a bunch of symlinks stripping out the target so that
    # things like `gcc` "just work", as long as we've got our path set properly
    for f in /opt/${target}/bin/${target}-*; do
        fbase=$(basename $f)
        # We don't worry about failure to create these symlinks, as sometimes there are files
        # name ridiculous things like ${target}-${target}-foo, which screws this up
        sudo ln -s $f /opt/${target}/bin/${fbase#${target}-} || true
    done
}

## Helper to install stage1 of glibc, e.g. the headers and crt1.o and friends
install_glibc_stage1()
{
    # First argument is the version
    glibc_url="http://mirrors.peers.community/mirrors/gnu/glibc/glibc-${glibc_version}.tar.xz"
    cd $system_root/src
    download_unpack.sh "${glibc_url}"

    # patch glibc for ARM
    cd $system_root/src/glibc-${glibc_version}
    
    # patch glibc to keep around libgcc_s_resume on arm
    # ref: https://sourceware.org/ml/libc-alpha/2014-05/msg00573.html
    if [[ "${target}" == arm* ]] || [[ "${target}" == aarch* ]]; then 
        patch -p1 < $system_root/downloads/patches/glibc_arm_gcc_fix.patch
    fi

    # Patch glibc's sunrpc cross generator to work with musl
    # See https://sourceware.org/bugzilla/show_bug.cgi?id=21604
    patch -p0 < $system_root/downloads/patches/glibc-sunrpc.patch

    # patch glibc's stupid gcc version check (we don't require this one, as if
    # it doesn't apply cleanly, it's probably fine)
    patch -p0 < $system_root/downloads/patches/glibc_gcc_version.patch || true

    # patch glibc's 32-bit assembly to withstand __i686 definition of newer GCC's
    # ref: http://comments.gmane.org/gmane.comp.lib.glibc.user/758
    if [[ "${target}" == i686* ]]; then
        patch -p1 < $system_root/downloads/patches/glibc_i686_asm.patch
    fi

    # patch for building old glibc on newer binutils
    patch -p0 < $system_root/downloads/patches/glibc_nocommon.patch

    # build glibc
    mkdir -p $system_root/src/glibc-${glibc_version}_build
    cd $system_root/src/glibc-${glibc_version}_build
    CFLAGS="-O2 -U_FORTIFY_SOURCE -D__i686=__i686 -fno-stack-protector" ${L32} $system_root/src/glibc-${glibc_version}/configure \
        --prefix=/opt/${target}/${target} \
        --host=${target} \
        --target=${target} \
        --with-headers=/opt/${target}/${target}/include \
        --with-binutils=/opt/${target}/bin \
        --enable-mulilib \
        --disable-werror \
        libc_cv_forced_unwind=yes \
        libc_cv_c_cleanup=yes

    ${L32} make -j${nproc} csu/subdir_lib
    sudo -E ${L32} make install-bootstrap-headers=yes install-headers

    sudo -E mkdir -p $system_root/opt/${target}/${target}/include/bits
    sudo -E mkdir -p $system_root/opt/${target}/${target}/include/gnu
    sudo -E mkdir -p $system_root/opt/${target}/${target}/lib

    # Manually copy over bits/stdio_lim.h
    sudo -E install bits/stdio_lim.h $system_root/opt/${target}/${target}/include/bits/

    # Manually copy over c runtime library object files
    sudo -E install csu/crt1.o csu/crti.o csu/crtn.o $system_root/opt/${target}/${target}/lib/

    # Create "stub" libc.so which is just empty
    sudo -E ${L32} ${target}-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $system_root/opt/${target}/${target}/lib/libc.so
    sudo -E touch $system_root/opt/${target}/${target}/include/gnu/stubs.h
}

# Helper to install the rest of glibc
install_glibc_stage2()
{
    cd $system_root/src/glibc-${glibc_version}_build
    sudo -E chown $(id -u):$(id -g) -R $system_root/src/glibc-${glibc_version}_build
    ${L32} make -j${nproc}
    sudo -E ${L32} make install

    # Cleanup
    cd $system_root/src
    sudo -E rm -rf glibc-${glibc_version}*
}


install_osx_sdk()
{
    # Download OSX SDK
    sdk_version="$(target_to_darwin_sdk ${target})"
    sdk_url="https://davinci.cs.washington.edu/MacOSX${sdk_version}.sdk.tar.xz"
    sudo mkdir -p $system_root/opt/${target}
    cd $system_root/opt/${target}
    sudo -E download_unpack.sh "${sdk_url}"

    # Fix weird permissions on the SDK folder
    sudo chmod 755 .
    sudo chmod 755 MacOSX*.sdk
}

install_libtapi()
{
    # Download libtapi
    libtapi_url=https://github.com/tpoechtrager/apple-libtapi/archive/${libtapi_version}.tar.gz
    cd $system_root/src
    download_unpack.sh "${libtapi_url}"

    cd $system_root/src/apple-libtapi-${libtapi_version}
    # Backport of https://reviews.llvm.org/D39297 to fix build on musl
    patch -p1 < $system_root/downloads/patches/libtapi_llvm_dynlib.patch

    # Build and install libtapi (We have to tell it to explicitly use clang)
    export MACOSX_DEPLOYMENT_TARGET=10.10
    export CC="clang"
    export CXX="clang++"
    INSTALLPREFIX=$system_root/opt/${target} ${L32} ./build.sh
    sudo -E INSTALLPREFIX=$system_root/opt/${target} ${L32} ./install.sh

    # Cleanup
    cd $system_root/src
    sudo -E rm -rf apple-libtapi-${libtapi_version}
}

install_cctools()
{
    # Download cctools
    cctools_url=https://github.com/tpoechtrager/cctools-port/archive/${cctools_version}.tar.gz
    cd $system_root/src
    download_unpack.sh "${cctools_url}"

    cd $system_root/src/cctools-port-${cctools_version}
    # Fix build on musl (https://github.com/tpoechtrager/cctools-port/pull/36)
    patch -p1 < $system_root/downloads/patches/cctools_musl.patch

    # Install cctools
    cd $system_root/src/cctools-port-${cctools_version}/cctools
    rm -f aclocal.m4
    ${L32} aclocal
    ${L32} libtoolize --force 
    ${L32} automake --add-missing --force
    ${L32} autoreconf
    ${L32} ./autogen.sh

    # cctools doesn't like 'x86_64h' target, so we strip out the 'h':
    ${L32} ./configure \
        --target=${target} \
        --prefix=/opt/${target} \
        --disable-clang-as \
        --with-libtapi=/opt/${target}
    ${L32} make -j${nproc}
    sudo -E ${L32} make install

    # Cleanup
    cd $system_root/src
    sudo -E rm -rf cctools-port-${cctools_version}
}

install_dsymutil()
{
    dsymutil_url=https://github.com/tpoechtrager/llvm-dsymutil/archive/${dsymutil_version}.tar.gz
    cd $system_root/src
    download_unpack.sh "${dsymutil_url}"

    cd $system_root/src/llvm-dsymutil-${dsymutil_version}
    # Backport of https://reviews.llvm.org/D39297 to fix build on musl
    patch -p1 < $system_root/downloads/patches/dsymutil_llvm_dynlib.patch

    # Install dsymutil
    mkdir -p $system_root/src/llvm-dsymutil-${dsymutil_version}/build
    cd $system_root/src/llvm-dsymutil-${dsymutil_version}/build
    ${L32} cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_TARGETS_TO_BUILD="X86" \
        -DLLVM_ENABLE_ASSERTIONS=Off
    ${L32} make -f tools/dsymutil/Makefile -j${nproc}
    sudo -E cp bin/llvm-dsymutil /opt/${target}/bin/dsymutil
    ${L32} make -f tools/llvm-ar/Makefile -j${nproc}
    sudo -E cp bin/llvm-ar /opt/${target}/bin/${target}-ar
    sudo -E cp bin/llvm-ranlib /opt/${target}/bin/${target}-ranlib

    # Cleanup
    cd $system_root/src
    sudo -E rm -rf llvm-dsymutil-${dsymutil_version}
}

install_mingw_stage1()
{
    mingw_url=https://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/mingw-w64-v${mingw_version}.tar.bz2
    cd $system_root/src
    download_unpack.sh "${mingw_url}"

    # Patch mingw to build 32-bit cross compiler with GCC 7.1+
    cd $system_root/src/mingw-w64-v${mingw_version}
    patch -p1 < /downloads/patches/mingw_gcc710_i686.patch

    # Install mingw headers
    cd $system_root/src/mingw-w64-v${mingw_version}/mingw-w64-headers
    ${L32} ./configure \
        --prefix=/opt/${target}/${target} \
        --enable-sdk=all \
        --enable-secure-api \
        --host=${target}
    
    sudo -E ${L32} make install
}

install_mingw_stage2()
{
    MINGW_CONF_ARGS=""
    if [[ "${target}" == i686-* ]]; then
        # If we're building a 32-bit build of mingw, add `--disable-lib64`
        MINGW_CONF_ARGS="${MINGW_CONF_ARGS} --disable-lib64"
    else
        MINGW_CONF_ARGS="${MINGW_CONF_ARGS} --disable-lib32"
    fi

    # Install crt
    mkdir -p $system_root/src/mingw-w64-v${mingw_version}-crt_build
    cd $system_root/src/mingw-w64-v${mingw_version}-crt_build
    ${L32} $system_root/src/mingw-w64-v${mingw_version}/mingw-w64-crt/configure \
        --prefix=/opt/${target}/${target} \
        --host=${target} \
        ${MINGW_CONF_ARGS}

    ${L32} make -j${nproc}
    sudo ${L32} make install

    # Install winpthreads
    mkdir -p $system_root/src/mingw-w64-v${mingw_version}-winpthreads_build
    cd $system_root/src/mingw-w64-v${mingw_version}-winpthreads_build
    ${L32} $system_root/src/mingw-w64-v${mingw_version}/mingw-w64-libraries/winpthreads/configure \
        --prefix=/opt/${target}/${target} \
        --host=${target} \
        --enable-static \
        --enable-shared

    ${L32} make -j${nproc}
    sudo ${L32} make install

    # Cleanup
    cd $system_root/src
    sudo -E rm -rf mingw-w64-v${mingw_version}*
}



# Ensure that PATH is setup properly
export PATH=$system_root/opt/${target}/bin:$PATH

