#!/usr/bin/env bash
set -e

ARCHS=("arm64-v8a" "armeabi-v7a")
BUILD_TYPE=Release
MGE_ARMV8_2_FEATURE_FP16=OFF
MGE_ARMV8_2_FEATURE_DOTPROD=OFF
MGE_DISABLE_FLOAT16=OFF
ARCH=arm64-v8a
REMOVE_OLD_BUILD=false
echo "EXTRA_CMAKE_ARGS: ${EXTRA_CMAKE_ARGS}"

function usage() {
    echo "$0 args1 args2 .."
    echo "available args detail:"
    echo "-d : Build with Debug mode, default Release mode"
    echo "-f : enable MGE_ARMV8_2_FEATURE_FP16 for ARM64, need toolchain and hardware support"
    echo "-p : enable MGE_ARMV8_2_FEATURE_DOTPROD for ARM64, need toolchain and hardware support"
    echo "-k : open MGE_DISABLE_FLOAT16 for NEON "
    echo "-a : config build arch available: ${ARCHS[@]}"
    echo "-r : remove old build dir before make, default off"
    echo "-h : show usage"
    echo "append other cmake config by export EXTRA_CMAKE_ARGS=..."
    echo "example: $0 -d"
    exit -1
}

while getopts "rkhdfpa:" arg
do
    case $arg in
        d)
            echo "Build with Debug mode"
            BUILD_TYPE=Debug
            ;;
        f)
            echo "enable MGE_ARMV8_2_FEATURE_FP16 for ARM64"
            MGE_ARMV8_2_FEATURE_FP16=ON
            ;;
        p)
            echo "enable MGE_ARMV8_2_FEATURE_DOTPROD for ARM64"
            MGE_ARMV8_2_FEATURE_DOTPROD=ON
            ;;
        k)
            echo "open MGE_DISABLE_FLOAT16 for NEON"
            MGE_DISABLE_FLOAT16=ON
            ;;
        a)
            tmp_arch=null
            for arch in ${ARCHS[@]}; do
                if [ "$arch" = "$OPTARG" ]; then
                    echo "CONFIG BUILD ARCH to : $OPTARG"
                    tmp_arch=$OPTARG
                    ARCH=$OPTARG
                    break
                fi
            done
            if [ "$tmp_arch" = "null" ]; then
                echo "ERR args for arch (-a)"
                echo "available arch list: ${ARCHS[@]}"
                usage
            fi
            ;;
        h)
            echo "show usage"
            usage
            ;;
        r)
            echo "config REMOVE_OLD_BUILD=true"
            REMOVE_OLD_BUILD=true
            ;;
        ?)
            echo "unkonw argument"
            usage
            ;;
    esac
done
echo "----------------------------------------------------"
echo "build config summary:"
echo "BUILD_TYPE: $BUILD_TYPE"
echo "MGE_ARMV8_2_FEATURE_FP16: $MGE_ARMV8_2_FEATURE_FP16"
echo "MGE_ARMV8_2_FEATURE_DOTPROD: $MGE_ARMV8_2_FEATURE_DOTPROD"
echo "MGE_DISABLE_FLOAT16: $MGE_DISABLE_FLOAT16"
echo "ARCH: $ARCH"
echo "----------------------------------------------------"

READLINK=readlink
MAKEFILE_TYPE="Unix"
OS=$(uname -s)

if [ $OS = "Darwin" ];then
    READLINK=greadlink
elif [[ $OS =~ "NT" ]]; then
    echo "BUILD in NT ..."
    MAKEFILE_TYPE="Unix"
fi

SRC_DIR=$($READLINK -f "`dirname $0`/../../")
source $SRC_DIR/scripts/cmake-build/utils/utils.sh

if [ -z $NDK_ROOT ];then
    echo "can not find NDK_ROOT env, pls export you NDK root dir to NDK_ROOT"
    exit -1
fi

function cmake_build() {
    BUILD_DIR=$SRC_DIR/build_dir/android/$1/$BUILD_TYPE/build
    INSTALL_DIR=$BUILD_DIR/../install
    BUILD_ABI=$1
    BUILD_NATIVE_LEVEL=$2
    echo "build dir: $BUILD_DIR"
    echo "install dir: $INSTALL_DIR"
    echo "build type: $BUILD_TYPE"
    echo "build ABI: $BUILD_ABI"
    echo "build native level: $BUILD_NATIVE_LEVEL"
    echo "BUILD MAKEFILE_TYPE: $MAKEFILE_TYPE"
    try_remove_old_build $REMOVE_OLD_BUILD $BUILD_DIR $INSTALL_DIR

    echo "create build dir"
    mkdir -p $BUILD_DIR
    mkdir -p $INSTALL_DIR
    cd $BUILD_DIR
    cmake -G "$MAKEFILE_TYPE Makefiles" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_ROOT/build/cmake/android.toolchain.cmake" \
        -DANDROID_NDK="$NDK_ROOT" \
        -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
        -DANDROID_ABI=$BUILD_ABI \
        -DANDROID_NATIVE_API_LEVEL=$BUILD_NATIVE_LEVEL \
        -DMGE_INFERENCE_ONLY=ON \
        -DMGE_WITH_CUDA=OFF \
        -DMGE_ARMV8_2_FEATURE_FP16= $MGE_ARMV8_2_FEATURE_FP16 \
        -DMGE_ARMV8_2_FEATURE_DOTPROD=$MGE_ARMV8_2_FEATURE_DOTPROD \
        -DMGE_DISABLE_FLOAT16=$MGE_DISABLE_FLOAT16 \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
        ${EXTRA_CMAKE_ARGS} \
        $SRC_DIR

    make -j$(nproc)
    make install/strip
}

build_flatc $SRC_DIR $REMOVE_OLD_BUILD

api_level=16
abi="armeabi-v7a with NEON"
IFS=""
if [ "$ARCH" = "arm64-v8a" ]; then
    api_level=21
    abi="arm64-v8a"
elif [ "$ARCH" = "armeabi-v7a" ]; then
    api_level=16
    abi="armeabi-v7a with NEON"
else
    echo "ERR CONFIG ABORT NOW!!"
    exit -1
fi
cmake_build $abi $api_level
