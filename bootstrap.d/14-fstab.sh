#
# Setup fstab and initramfs
#

# Load utility functions
. ./functions.sh

# Install and setup fstab
install_readonly files/mount/fstab "${ETC_DIR}/fstab"

# Add usb/sda disk root partition to fstab
if [ "$ENABLE_SPLITFS" = true ] && [ "$ENABLE_CRYPTFS" = false ] ; then
  sed -i "s/mmcblk0p2/sda1/" "${ETC_DIR}/fstab"
fi

# Add encrypted root partition to fstab and crypttab
if [ "$ENABLE_CRYPTFS" = true ] ; then
  # Replace fstab root partition with encrypted partition mapping
  sed -i "s/mmcblk0p2/mapper\/${CRYPTFS_MAPPING}/" "${ETC_DIR}/fstab"

  # Add encrypted partition to crypttab and fstab
  install_readonly files/mount/crypttab "${ETC_DIR}/crypttab"
  echo "${CRYPTFS_MAPPING} /dev/mmcblk0p2 none luks,initramfs" >> "${ETC_DIR}/crypttab"

  if [ "$ENABLE_SPLITFS" = true ] ; then
    # Add usb/sda disk to crypttab
    sed -i "s/mmcblk0p2/sda1/" "${ETC_DIR}/crypttab"
  fi
fi

# Generate initramfs file
if [ "$BUILD_KERNEL" = true ] && [ "$ENABLE_INITRAMFS" = true ] ; then
  if [ "$ENABLE_CRYPTFS" = true ] ; then
    # Include initramfs scripts to auto expand encrypted root partition
    if [ "$EXPANDROOT" = true ] ; then
      install_exec files/initramfs/expand_encrypted_rootfs "${ETC_DIR}/initramfs-tools/scripts/init-premount/expand_encrypted_rootfs"
      install_exec files/initramfs/expand-premount "${ETC_DIR}/initramfs-tools/scripts/local-premount/expand-premount"
      install_exec files/initramfs/expand-tools "${ETC_DIR}/initramfs-tools/hooks/expand-tools"
    fi
	
	if [ "$CRYPTFS_DROPBEAR" = true ]; then
		if [ -n "$CRYPTFS_DROPBEAR_PUBKEY" = true ] && [ -f "$CRYPTFS_DROPBEAR_PUBKEY" = true ] ; then
 			install_readonly $"CRYPTFS_DROPBEAR_PUBKEY" "${ETC_DIR}/dropbear-initramfs/id_rsa.pub"
 			chroot_exec cat /etc/dropbear-initramfs/id_rsa.pub | chroot_exec tee -a /etc/dropbear-initramfs/authorized_keys
 		else
 			#SAVE THE GENERATED KEYS in mounted folder
 			#mkdir -p ${DROPBEAR_KEY_DIR}
 			#mkdir -p ${ETC_DIR}/dropbear-initramfs/keys
 			#mount --bind ${DROPBEAR_KEY_DIR} ${ETC_DIR}/dropbear-initramfs/keys
 			#cp ${ETC_DIR}/dropbear-initramfs/id_rsa.pub ${ETC_DIR}/dropbear-initramfs/keys/id_rsa.pub
 			#DROPBEAR_KEYDIR=${ETC_DIR}/dropbear-initramfs/keys
 
 			#create keys
 			chroot_exec /usr/bin/dropbearkey -t rsa -f /etc/dropbear-initramfs/id_rsa.dropbear
			
 			#convert dropbear key to openssh key
 			chroot_exec /usr/lib/dropbear/dropbearconvert dropbear openssh /etc/dropbear-initramfs/id_rsa.dropbear /etc/dropbear-initramfs/id_rsa
			
			#Get Public Key Part
			chroot_exec touch /etc/dropbear-initramfs/id_rsa.pub
 			chroot_exec /usr/bin/dropbearkey -y -f /etc/dropbear-initramfs/id_rsa.dropbear | chroot_exec tee /etc/dropbear-initramfs/id_rsa.pub
 			#delete unwanted lines
 			chroot_exec sed -i '/Public/d' /etc/dropbear-initramfs/id_rsa.pub
 			chroot_exec sed -i '/Fingerprint/d' /etc/dropbear-initramfs/id_rsa.pub
 
			#Trust the new key
 			chroot_exec touch /etc/dropbear-initramfs/authorized_keys
 			chroot_exec cat /etc/dropbear-initramfs/id_rsa.pub | chroot_exec tee -a /etc/dropbear-initramfs/authorized_keys
			
			#Get unlock script
 			install_readonly files/initramfs/crypt_unlock.sh "${ETC_DIR}/initramfs-tools/hooks/crypt_unlock.sh"
 			chroot_exec chmod +x /etc/initramfs-tools/hooks/crypt_unlock.sh

	else
		# Disable SSHD inside initramfs
		printf "#\n# DROPBEAR: [ y | n ]\n#\n\nDROPBEAR=n\n" >> "${ETC_DIR}/initramfs-tools/initramfs.conf"
	fi

    # Add cryptsetup modules to initramfs
    printf "#\n# CRYPTSETUP: [ y | n ]\n#\n\nCRYPTSETUP=y\n" >> "${ETC_DIR}/initramfs-tools/conf-hook"

    # Dummy mapping required by mkinitramfs
    echo "0 1 crypt $(echo ${CRYPTFS_CIPHER} | cut -d ':' -f 1) ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff 0 7:0 4096" | chroot_exec dmsetup create "${CRYPTFS_MAPPING}"

    # Generate initramfs with encrypted root partition support
    chroot_exec mkinitramfs -o "/boot/firmware/initramfs-${KERNEL_VERSION}" "${KERNEL_VERSION}"

    # Remove dummy mapping
    chroot_exec cryptsetup close "${CRYPTFS_MAPPING}"
  else
    # Generate initramfs without encrypted root partition support
    chroot_exec mkinitramfs -o "/boot/firmware/initramfs-${KERNEL_VERSION}" "${KERNEL_VERSION}"
  fi
fi
