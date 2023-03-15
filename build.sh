#!/bin/bash -xe
set -xe

function parseArgs(){
   for change in "$@"; do
      name="${change%%=*}"
      value="${change#*=}"
      eval $name="$value"
   done
}

function stripArchive(){
    local target=""
	parseArgs $@

	local striptool="$(which ${STRIP})"
    if [ ! -f "${striptool}" ]; then
        echo "Need a stripper. Cannot continue!"
        exit -1
    fi
	find . -name "*.a" -exec ${STRIP} --strip-debug --strip-unneeded -p {} \;
	find . -name "*.so*" -exec ${STRIP} --strip-all -p {} \;
}


function package(){
    local artifacts_url="/home/${USER}/Downloads"
    local target=""
    local library="zlib"
	parseArgs $@
	local workdir=installs
	mkdir -p "${workdir}"
    rm -fr ${workdir}/*

	mkdir -p "${workdir}/include"
	rsync -uav *.h "${workdir}/include/"
	mkdir -p "${workdir}/lib"
    if [ "${target}" == "mingw" ]; then
        rsync -uav ${target}-build/lib*.dll* "${workdir}/lib/"
    else
        rsync -uav ${target}-build/lib*.so* "${workdir}/lib/"
    fi

    pushd "${workdir}/lib/"
    stripArchive target="${target}"
    popd

    local SHA="$(sudo git config --global --add safe.directory .;sudo git rev-parse --verify --short HEAD)"
    local output="${library}-${SHA}-${target}.tar.xz"
    tar -cvJf "${output}" "${workdir}"

    if [ "${artifacts_url:0:8}" == "https://" ]; then
        echo "Not implemented! I quit."
        exit -1
    elif [ "${artifacts_url:0:1}" == "/" ] && [ -d "${artifacts_url}" ]; then
        cp -f "${output}" "${artifacts_url}/${artifacts_file}"
    fi
    mv -f "${output}" "${target}-build/"
    #rm -fr "${workdir}"
}

function sourceToolchainsFile(){
    local target="x86"
    local cmake_toolchain_file
    local bash_toolchain_file
    parseArgs $@

    if [ "$target" == "mingw" ]; then
        local workdir=$(mktemp -d)
        local curdir="$(pwd)"
        pushd "${workdir}"
        git clone --no-checkout --depth 1 git@github.com:jambamamba/utils.git
        cd utils
        local toolchainfile="x86_64-w64-mingw32.cmake"
        cmake_toolchain_file="${curdir}/${toolchainfile}"
        git show main:toolchains/${toolchainfile} > "${cmake_toolchain_file}"
        local toolchainfile="x86_64-w64-mingw32.sh"
        bash_toolchain_file="${curdir}/${toolchainfile}"
        git show main:toolchains/${toolchainfile} > "${bash_toolchain_file}"
        popd
        # rm -fr "${workdir}"
        if [ ! -f "${curdir}/${toolchainfile}" ]; then
            echo "Need full path to toolchain bash script that can be sourced"
            exit -1
        fi
        source "${bash_toolchain_file}"
    elif [ "$target" == "arm" ]; then
        local toolchainfile="${SDK_DIR}/environment-setup-aarch64-fslc-linux"
        if [ ! -f "${toolchainfile}" ]; then
            echo "Need full path to toolchain bash script that can be sourced"
            exit -1
        fi
        sudo mv -f ${SDK_DIR}/sysroots/x86_64-fslcsdk-linux/usr/bin/perl ${SDK_DIR}/sysroots/x86_64-fslcsdk-linux/usr/bin/perl.backup
        sudo ln -sf /usr/bin/perl ${SDK_DIR}/sysroots/x86_64-fslcsdk-linux/usr/bin/perl

        source ${toolchainfile}
        unset CROSS_COMPILE
        #sudo mv -f ${SDK_DIR}/sysroots/x86_64-fslcsdk-linux/usr/bin/perl.backup ${SDK_DIR}/sysroots/x86_64-fslcsdk-linux/usr/bin/perl
    else
        export STRIP=$(which strip)
    fi
}

function skipBuild(){
    local target="x86"
    parseArgs $@
    local builddir="${target}-build"

    if [ "$target" == "mingw" ] && \
        [ -f "${builddir}/libzlib.dll" ]; then 
        return 1
    elif [ "$target" == "x86" ] && \
        [ -f "${builddir}/libz.so.1.2.13" ]; then 
        return 1
    elif [ "$target" == "arm" ] && \
        [ -f "${builddir}/libz.so.1.2.13" ]; then 
        return 1
    fi
    return 0
}

function build(){
    local clean=""
    local target="x86"
    local cmake_toolchain_file=""
    parseArgs $@
    
    local builddir="${target}-build"
    mkdir -p "${builddir}"
    # local postfix="-1.1.1t"

    if [ "$clean" == "true" ]; then
        rm -fr "${builddir}/*"
    fi

    local script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    export ZLIB_LIBRARY=${script_dir}
    export ZLIB_INCLUDE_DIR=${script_dir}
    pushd "${builddir}"

    if [ "$target" == "mingw" ]; then
            # -DCMAKE_MODULE_PATH=$(pwd)/../../cmake-modules \
            # -DCMAKE_PREFIX_PATH=$(pwd)/../../cmake-modules \
        cmake -DCMAKE_TOOLCHAIN_FILE=${cmake_toolchain_file} \
            -DCMAKE_INSTALL_BINDIR=$(pwd) \
            -DCMAKE_INSTALL_LIBDIR=$(pwd) \
            -DCMAKE_SKIP_RPATH=TRUE \
            -DCMAKE_SKIP_INSTALL_RPATH=TRUE \
            -DWIN32=TRUE \
            -DMINGW64=${MINGW64} \
            -DWITH_GCRYPT=OFF \
            -DWITH_MBEDTLS=OFF \
            -DHAVE_STRTOULL=1 \
            -DHAVE_COMPILER__FUNCTION__=1 \
            -DHAVE_GETADDRINFO=1 \
            -DENABLE_CUSTOM_COMPILER_FLAGS=OFF \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_CLAR=OFF \
            -DTHREADSAFE=ON \
            -DCMAKE_SYSTEM_NAME=Windows \
            -DCMAKE_C_COMPILER=$CC \
            -DCMAKE_RC_COMPILER=$RESCOMP \
            -DDLLTOOL=$DLLTOOL \
            -DCMAKE_FIND_ROOT_PATH=/usr/x86_64-w64-mingw32 \
            -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
            -DCMAKE_INSTALL_PREFIX=../install-win \
            -G "Ninja" ..
        ninja
    elif [ "$target" == "arm" ] || [ "$target" == "x86" ]; then
        cmake -DBUILD_SHARED_LIBS=ON ..
        VERBOSE=1 make -j
    fi
    popd
}

function main(){
    local cmake_toolchain_file=""
    local bash_toolchain_file=""
    skipBuild $@

    sourceToolchainsFile $@ cmake_toolchain_file="" bash_toolchain_file=""
    build $@ cmake_toolchain_file="${cmake_toolchain_file}"
    package $@ library="zlib"
}

main $@