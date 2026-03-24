#!/bin/bash
# Pre-flight check for AMD GPU Passthrough on Proxmox
# Target Hardware: Minisforum UM890 Pro (Radeon 780M)

echo "--- Proxmox Host Passthrough Check ---"

# 1. Check IOMMU Status
if dmesg | grep -E 'AMD-Vi|IOMMU' | grep -q 'enabled'; then
    echo "[OK] IOMMU is enabled in the kernel."
else
    echo "[FAIL] IOMMU not detected. Check /etc/default/grub for 'amd_iommu=on iommu=pt'"
fi

# 2. Check Kernel Modules
MODULES=("vfio" "vfio_iommu_type1" "vfio_pci")
for mod in "${MODULES[@]}"; do
    if lsmod | grep -q "$mod"; then
        echo "[OK] Module $mod is loaded."
    else
        echo "[FAIL] Module $mod is MISSING. Add it to /etc/modules"
    fi
done

# 3. Identify the Radeon 780M at c5:00.0
GPU_INFO=$(lspci -nn | grep "c5:00.0")
GPU_ID=$(echo $GPU_INFO | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])')

if [ -z "$GPU_ID" ]; then
    echo "[FAIL] Could not find GPU at c5:00.0. Run 'lspci | grep VGA' to verify address."
else
    echo "[OK] Found AMD GPU at c5:00.0 with IDs: $GPU_ID"
    
    # Check if vfio-pci has claimed it
    if lspci -k -s c5:00.0 | grep -q "vfio-pci"; then
        echo "[OK] Kernel driver 'vfio-pci' has claimed the GPU. Ready for VM."
    else
        echo "[WARN] Host driver (amdgpu) is still holding the GPU."
        echo "       Action: Add 'options vfio-pci ids=$GPU_ID' to /etc/modprobe.d/vfio.conf"
    fi
fi