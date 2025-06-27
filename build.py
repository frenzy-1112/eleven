# build.py
import os
import subprocess
import sys

# Define key paths
kernel_dir = os.getcwd()
objdir = f"{kernel_dir}/out"
kf = f"{kernel_dir}/packaging"
clang_path = f"{kernel_dir}/clang-llvm/bin"
avbtool = f"{kernel_dir}/scripts/avb/avbtool.py"
ZIMAGE = f"{objdir}/arch/arm64/boot/Image.gz-dtb"
DTBOIMAGE = f"{objdir}/arch/arm64/boot/dtbo.img"
zip_name = "FlashableKernel.zip"

# Set environment variables
os.environ["ARCH"] = "arm64"
os.environ["SUBARCH"] = "arm64"
os.environ["CONFIG_FILE"] = "avicii_defconfig debugfs.config"
os.environ["CCACHE"] = subprocess.getoutput("command -v ccache")
os.environ["PATH"] = f"{clang_path}:{os.environ['PATH']}"
os.environ["CC"] = "ccache clang"
os.environ["CLANG_TRIPLE"] = "aarch64-linux-gnu-"
os.environ["CROSS_COMPILE"] = "aarch64-linux-gnu-"
os.environ["CROSS_COMPILE_ARM32"] = "arm-linux-gnueabi-"
os.environ["LLVM"] = "1"
os.environ["LLVM_IAS"] = "1"

def run_command(cmd, cwd=None):
    result = subprocess.run(cmd, shell=True, cwd=cwd)
    if result.returncode != 0:
        print(f"[X] Failed: {cmd}")
        sys.exit(1)

def make_defconfig():
    print("[*] Generating defconfig...")
    run_command(f"make O=out {os.environ['CONFIG_FILE']}")

def compile_kernel():
    print("[*] Compiling the kernel...")
    run_command(f"make O=out -j$(nproc) 2>&1 | tee error.log")
    run_command(f"python3 {avbtool} add_hash_footer --image {DTBOIMAGE} --partition_size 25165824 --partition_name dtbo")

def package_kernel():
    print("[*] Packaging kernel into flashable ZIP...")
    if os.path.isfile(ZIMAGE) and os.path.isfile(DTBOIMAGE):
        os.makedirs(kf, exist_ok=True)
        subprocess.run(f"cp {ZIMAGE} {DTBOIMAGE} {kf}", shell=True)
        os.chdir(kf)
        subprocess.run("find . -name '*.zip' -delete", shell=True)
        subprocess.run(f"zip -r9 {zip_name} * -x .git README.md *.zip", shell=True)
        subprocess.run(f"mv {zip_name} $HOME/{zip_name}", shell=True)
        print(f"[OK] Flashable ZIP created at: $HOME/{zip_name}")
    else:
        print("[X] Missing kernel or dtbo image.")
        sys.exit(1)

make_defconfig()
compile_kernel()
package_kernel()
