#!/bin/bash

# Variables
base_dir=$(pwd)
work_dir="${base_dir}/work"
backup_dir="${base_dir}/backup"
repo_dir="${base_dir}/repo"
kernel_version="5.15"
re4son_repo="https://github.com/Re4son/re4son-raspberrypi-linux"
nexmon_repo="https://github.com/seemoo-lab/nexmon"
firmware_repo="https://github.com/raspberrypi/firmware"
nexmon_branch="master"
kernel_branch="rpi-5.15.32-re4son"
firmware_branch="1.20220331"

# Functions
status() {
    echo "[$(date +"%T")] $1"
}

backup_kernel() {
    status "Backing up current kernel"
    mkdir -p "${backup_dir}/boot"
    mkdir -p "${backup_dir}/lib/modules"
    cp -rf /boot/* "${backup_dir}/boot/"
    cp -rf /lib/modules/* "${backup_dir}/lib/modules/"
    status "Backup completed"
}

restore_kernel() {
    status "Restoring the old kernel"
    cp -rf "${backup_dir}/boot/"* /boot/
    cp -rf "${backup_dir}/lib/modules/"* /lib/modules/
    status "Restore completed"
}

clone_and_patch_kernel() {
    status "Cloning and patching the kernel"
    
    # Clone firmware
    git clone -b "${firmware_branch}" --depth 1 "${firmware_repo}" "${work_dir}/rpi-firmware"
    cp -rf "${work_dir}/rpi-firmware/boot/"* "${work_dir}/boot/"
    cp -rf "${work_dir}/rpi-firmware/opt/"* "${work_dir}/opt/"
    rm -rf "${work_dir}/rpi-firmware"
    
    # Clone Nexmon firmware
    git clone "${nexmon_repo}" -b "${nexmon_branch}" "${base_dir}/nexmon" --depth 1
    
    # Clone and build the kernel
    git clone --depth 1 "${re4son_repo}" -b "${kernel_branch}" "${work_dir}/usr/src/kernel"
    cd "${work_dir}/usr/src/kernel"
    
    # Set default defconfig
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcmrpi_defconfig
    
    # Build kernel
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)
    
    # Make kernel modules
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- modules_install INSTALL_MOD_PATH="${work_dir}"
    
    # Copy kernel to boot
    perl scripts/mkknlimg --dtok arch/arm/boot/zImage "${work_dir}/boot/kernel.img"
    cp arch/arm/boot/dts/*.dtb "${work_dir}/boot/"
    cp arch/arm/boot/dts/overlays/*.dtb* "${work_dir}/boot/overlays/"
    cp arch/arm/boot/dts/overlays/README "${work_dir}/boot/overlays/"
    
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- mrproper
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcmrpi_defconfig
    
    # Fix up the symlink for building external modules
    kernver=$(ls "${work_dir}/lib/modules/")
    cd "${work_dir}/lib/modules/${kernver}"
    rm build
    rm source
    ln -s /usr/src/kernel build
    ln -s /usr/src/kernel source
    cd "${base_dir}"
}

build_nexmon() {
    status "Building Nexmon firmware"
    cd "${base_dir}/nexmon"
    
    # Make sure we're not still using the armel cross compiler
    unset CROSS_COMPILE
    
    # Disable statistics
    touch DISABLE_STATISTICS
    source setup_env.sh
    make
    cd buildtools/isl-0.10
    CC=$CCgcc
    ./configure
    make
    sed -i -e 's/all:.*/all: $(RAM_FILE)/g' "${NEXMON_ROOT}/patches/bcm43436b03/9_88_4_65/nexmon/Makefile"
    cd "${NEXMON_ROOT}/patches/bcm43436b03/9_88_4_65/nexmon"
    make clean
    
    # We do this so we don't have to install the ancient isl version into /usr/local/lib on systems
    LD_LIBRARY_PATH="${NEXMON_ROOT}/buildtools/isl-0.10/.libs" make ARCH=arm CC="${NEXMON_ROOT}/buildtools/gcc-arm-none-eabi-5_4-2016q2-linux-x86/bin/arm-none-eabi-"
    
    # RPi Zero 2 W firmware
    mkdir -p "${work_dir}/lib/firmware/brcm"
    cp "${NEXMON_ROOT}/patches/bcm43436b03/9_88_4_65/nexmon/brcmfmac43436-sdio.bin" "${work_dir}/lib/firmware/brcm/brcmfmac43436-sdio.nexmon.bin"
    cp "${NEXMON_ROOT}/patches/bcm43436b03/9_88_4_65/nexmon/brcmfmac43436-sdio.bin" "${work_dir}/lib/firmware/brcm/brcmfmac43436-sdio.bin"
    wget https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43436-sdio.txt -O "${work_dir}/lib/firmware/brcm/brcmfmac43436-sdio.txt"
    
    # Make a backup copy of the rpi firmware in case people don't want to use the nexmon firmware
    wget https://raw.githubusercontent.com/RPi-Distro/firmware-nonfree/master/brcm/brcmfmac43436-sdio.bin -O "${work_dir}/lib/firmware/brcm/brcmfmac43436-sdio.rpi.bin"
}

# Main
if [ "$1" == "backup" ]; then
    backup_kernel
elif [ "$1" == "restore" ]; then
    restore_kernel
else
    mkdir -p "${work_dir}" "${repo_dir}" "${backup_dir}/lib/modules"
    backup_kernel
    clone_and_patch_kernel
    build_nexmon
    status "Kernel patching and Nexmon build complete"
fi
