#!/bin/bash

# Kernel build script for Android arm64
# Cleaned, CI-compatible, assumes AnyKernel3 is present in repo

msg() {
    echo -e "\e[1;32m$*\e[0m"
}

err() {
    echo -e "\e[1;41m$*\e[0m"
    exit 1
}

# Constants
green='\033[01;32m'
default='\033[0m'

# Kernel info
KERNEL_DIR=$PWD
VERSION="X2-Chidori"
DEVICE="avicii"
DEFCONFIG=vendor/lito-perf_defconfig
COMPILER=clang
INCREMENTAL=0
DEF_REG=1
BUILD_DTBO=1
SILENCE=0
ZIPNAME="Escrima-$VERSION"
DATE=$(TZ=Asia/Kolkata date +"%Y%m%d-%H%M%S")

# Output & Toolchain Paths
TC_DIR="$HOME/clang-llvm"
UFDT_DIR="$HOME/scripts/ufdt/libufdt"
OUT_DIR="$KERNEL_DIR/out"
AK3_DIR="$KERNEL_DIR/AnyKernel3"

clone() {
    echo " "
    if [ "$COMPILER" = "clang" ]; then
        msg "🔧 Cloning Proton Clang"
        git clone --depth=1 -q https://github.com/kdrag0n/proton-clang.git "$TC_DIR"
    else
        msg "🔧 Cloning GCC toolchains"
        git clone --depth=1 -q https://github.com/arter97/arm64-gcc.git gcc64
        git clone --depth=1 -q https://github.com/arter97/arm32-gcc.git gcc32
        GCC64_DIR=$KERNEL_DIR/gcc64
        GCC32_DIR=$KERNEL_DIR/gcc32
    fi

    msg "📦 Cloning libufdt"
    git clone --depth=1 -q https://android.googlesource.com/platform/system/libufdt "$UFDT_DIR"
}

exports() {
    export KBUILD_BUILD_USER="ajit"
    export KBUILD_BUILD_HOST="github-actions"
    export ARCH=arm64
    export SUBARCH=arm64

    if [ "$COMPILER" = "clang" ]; then
        KBUILD_COMPILER_STRING=$("$TC_DIR"/bin/clang --version | head -n1)
        PATH=$TC_DIR/bin:$PATH
    else
        KBUILD_COMPILER_STRING=$("$GCC64_DIR"/bin/aarch64-elf-gcc --version | head -n1)
        PATH=$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH
    fi

    export PATH KBUILD_COMPILER_STRING
    export PROCS=$(nproc --all)
}

build_kernel() {
    [ "$INCREMENTAL" = 0 ] && {
        msg "🧹 Cleaning Sources"
        make clean && make mrproper
        rm -rf "$OUT_DIR" "$AK3_DIR/Image" "$AK3_DIR"/*.zip
    }

    make O="$OUT_DIR" "$DEFCONFIG"

    if [ "$DEF_REG" = 1 ]; then
        cp .config arch/arm64/configs/"$DEFCONFIG"
        git add arch/arm64/configs/"$DEFCONFIG"
        git diff --quiet || git commit -m "$DEFCONFIG: Regenerate — auto-generated"
    fi

    BUILD_START=$(date +%s)

    MAKE_ARGS=()
    if [ "$COMPILER" = "clang" ]; then
        MAKE_ARGS+=(
            CROSS_COMPILE=aarch64-linux-gnu-
            CROSS_COMPILE_ARM32=arm-linux-gnueabi-
            CC=clang
            AR=llvm-ar
            OBJDUMP=llvm-objdump
            STRIP=llvm-strip
            NM=llvm-nm
            OBJCOPY=llvm-objcopy
            LD=ld.lld
        )
    else
        MAKE_ARGS+=(
            CROSS_COMPILE=aarch64-elf-
            CROSS_COMPILE_ARM32=arm-eabi-
            AR=aarch64-elf-ar
            OBJDUMP=aarch64-elf-objdump
            STRIP=aarch64-elf-strip
        )
    fi

    [ "$SILENCE" = "1" ] && MAKE_ARGS+=(-s)

    msg "🛠️  Starting Compilation"
    make -j"$PROCS" O="$OUT_DIR" "${MAKE_ARGS[@]}" 2>&1

    if [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
        msg "✅ Kernel compiled successfully"

        if [ "$BUILD_DTBO" = 1 ]; then
            msg "📦 Building DTBO"
            DTBO_SOURCE="$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/avicii-overlay-dvt.dtbo"
            DTBO_OUTPUT="$OUT_DIR/arch/arm64/boot/dtbo.img"
            PYTHON=$(command -v python2 || command -v python3)

            "$PYTHON" "$UFDT_DIR/utils/src/mkdtboimg.py" create "$DTBO_OUTPUT" \
                --page_size=4096 "$DTBO_SOURCE"
        fi

        gen_zip
    else
        err "❌ Kernel build failed!"
    fi
}

gen_zip() {
    msg "📦 Creating flashable zip"
    cp "$OUT_DIR/arch/arm64/boot/Image" "$AK3_DIR/"
    [ -f "$OUT_DIR/arch/arm64/boot/dtbo.img" ] && cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$AK3_DIR/"

    cd "$AK3_DIR" || exit
    zip -r9 "$ZIPNAME-$DEVICE-$DATE.zip" * -x .git README.md
    cd ..

    msg "✅ Flashable zip created at: $AK3_DIR/$ZIPNAME-$DEVICE-$DATE.zip"
}

# Run build
clone
exports
build_kernel

BUILD_END=$(date +%s)
DIFF=$((BUILD_END - BUILD_START))
echo -e "$green Build completed in $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s).$default"

exit 0
