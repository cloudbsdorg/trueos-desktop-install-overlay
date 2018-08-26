#!/bin/sh
# Script to run on install media and load optional video packages
# post install

# TODO add video detection routines


detect_video() {

  # First detect if the boottype is "UEFI" or not (legacy)
  efi=`sysctl -nq machdep.bootmethod`
  # Detect the vendor/device info for the graphics card
  vendor=`pciconf -lv vgapci0 2>/dev/null | grep vendor | cut -d \' -f 2`
  device=`pciconf -lv vgapci0 2>/dev/null | grep device | cut -d \' -f 2`

  #  -- NOTE: For each match listed here, add the vendor -> driver logic below as well
  MATCHES="nvidia:nvidia intel:intel innotek:vbox amd:amd vmware:vmware"
  for match in ${MATCHES}
  do
    echo "${vendor}" | grep -qi `echo ${match} | cut -d : -f 1`
    if [ $? -eq 0 ] ; then
      vendor_detected=`echo ${match} | cut -d : -f 2`
      break
    fi
  done

  #Now determine the driver based on the detected vendor
  if [ "${vendor_detected}" = "intel" ] ; then
    if [ "${efi}" = "UEFI" ] ; then
      driver="modesetting"
    else
      driver="intel"
    fi
  elif [ "${vendor_detected}" = "nvidia" ] ; then
    driver="nvidia"
  elif [ "${vendor_detected}" = "vbox" ] ; then
    driver="vboxvideo"
  elif [ "${vendor_detected}" = "amd" ] ; then
    driver="amdgpu"
  elif [ "${vendor_detected}" = "vmware" ] ; then
    driver="vmware"
  else
    # Couldn't detect, going to have to trust Xorg here
    driver="auto"
  fi

  echo ${driver}
  exit 0
}

setup_video() {

  viddriver="$(detect_video)"

  # Package install this new driver if necessary
  case $viddriver in
     modesetting) pkg -r ${FSMNT} install -y -f drm-next-kmod
		  sysrc -f ${FSMNT}/etc/rc.conf kldload_drm="/boot/modules/i915kms.ko"
                  ;;
     nvidia) pkg -r ${FSMNT} install -y -f nvidia-driver nvidia-settings nvidia-xconfig ;;
     *) ;;
  esac

  #Get the bus ID for the video card
  busid=`pciconf -lv vgapci0 | grep vgapci0 | cut -d : -f 2-4`

  #Now copy over the xorg.conf template and replace the driver/busid in it
  template="/root/plasma-xorg.conf"
  cp -f "${template}" "${FSMNT}/etc/X11/xorg.conf"
  sed -i '' "s|%%BUSID%%|${busid}|g" "${FSMNT}/etc/X11/xorg.conf"
  sed -i '' "s|%%DRIVER%%|${viddriver}|g" "${FSMNT}/etc/X11/xorg.conf"

}

setup_zfs_arc() {

  # Tune ZFS ARC
  ###############################################

  grep -q "vfs.zfs.arc_max=" /boot/loader.conf
  if [ $? -eq 0 ] ; then
    return 0 #Do not overwrite current ARC settings
  fi

  # Get system memory in bytes
  sysMem=`sysctl hw.physmem | cut -w -f 2`
  # Get that in MB
  sysMem=`expr $sysMem / 1024 / 1024`
  # Set some default zArc sizes based upon RAM of system
  if [ $sysMem -lt 1024 ] ; then
    zArc="128"
  elif [ $sysMem -lt 2048 ] ; then
    zArc="256"
  elif [ $sysMem -lt 4096 ] ; then
    zArc="512"
  else
    zArc="1024"
  fi

  echo "# Tune ZFS Arc Size - Change to adjust memory used for disk cache" >> ${FSMNT}/boot/loader.conf
  echo "vfs.zfs.arc_max=\"${zArc}M\"" >> ${FSMNT}/boot/loader.conf
}

#figure out if this is a laptop or not (has a battery)
numBat=`apm | grep "Number of batteries:" | cut -d : -f 2`
if [ $numBat -lt 1 ] ; then
  #invalid apm battery status = no batteries
  type="desktop"
else
  type="laptop"
fi

# Set some sane ZFS arc sizes
setup_zfs_arc

# Install video drivers
setup_video
