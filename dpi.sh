#!/bin/bash

#############################
#			    #
# Debian Preseed Integrator #
#			    #
#############################

## Test prerequisites

# Loop device support

distroversion=`cat /etc/issue | awk {'print$1'} | head -1`
loopmodule=`lsmod | grep loop`

if [ $distroversion == 'Debian' ]; then
        if [ -z "$loopmodule" ]; then
                echo "loop module is missing: modprobe loop"
                exit 1
        fi
fi

# Binaries

declare -a binaries=("curl" "rsync" "wget" "xorriso")

binariesamount=${#binaries[@]}

for (( i=1; i<${binariesamount}+1; i++ ));
do
	if [ ! -f /usr/bin/${binaries[$i-1]} ]; then
		echo ${binaries[$i-1]} is missing: apt-get install ${binaries[$i-1]}
		exit 1
	fi
done

## Settings

maindir=/var/local/dpi
url=http://cdimage.debian.org/cdimage/unofficial/non-free/cd-including-firmware/current/amd64/iso-cd
checksum=$(curl -sL http://cdimage.debian.org/cdimage/unofficial/non-free/cd-including-firmware/current/amd64/iso-cd/SHA512SUMS | awk '{print $1}')
content=$(curl -sL $url/)
version=$(grep 'netinst.iso">firmware' <<< "$content" | grep -oPm1 "(\d\.\d\.\d)" | head -1)
strippedversion=$(echo "$version" | tr -d .)

## Create work dirs

if [ ! -e $maindir ] ; then
        mkdir $maindir
fi

declare -a subdirs=("cd" "iso" "mnt" "preseed")

subdirsamount=${#subdirs[@]}

for (( i=1; i<${subdirsamount}+1; i++ ));
do
        if [ ! -e $maindir/${subdirs[$i-1]} ]; then
                mkdir $maindir/${subdirs[$i-1]}
        fi
done

## Fetch latest stable Debian Netinstall ISO image - the firmware one so it works with more NICs

cd $maindir/iso

if [ ! -f "firmware-${version}-amd64-netinst.iso" ]; then
	echo "Downloading latest ISO image"
	echo -n "Downloading firmware-"$version"-amd64-netinst.iso"
	echo -n "     "
	declare -a wgetreturn
	wget --progress=dot $url/firmware-"$version"-amd64-netinst.iso 2>&1 | grep --line-buffered "%" | sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
	wgetreturn=( "${PIPESTATUS[@]}" )
	echo -ne "\b\b\b\b"
	if [[ $wgetreturn -ne 0 ]]; then
		echo "-> Error downloading latest ISO"
		exit 1
        fi
	echo -n "-> "
fi

## Verify checksum

checksumdownload=$(sha512sum firmware-"$version"-amd64-netinst.iso | awk '{print $1}')

if [ ! $sum == $checksum ]; then
	echo "Download corrupt - deleted - retry again"
	rm -f firmware-"$version"-amd64-netinst.iso
	exit 1
else
	echo "Checksum verified OK"
fi

## Mount iso

echo "Mounting the ISO"
/bin/mount -o loop $maindir/iso/firmware-"$version"-amd64-netinst.iso $maindir/mnt/ >/dev/null 2>&1

## Copy readonly .iso data to a clean cd/ location for changes

echo "Cleaning the previous workdir with writable ISO content"
cd $maindir
rm -rf cd/
mkdir cd

echo "Syncing the content from the original read-only ISO image to the writable location"
/usr/bin/rsync -a -H --exclude=TRANS.TBL mnt/ cd

echo "Unmounting the read-only image"
/bin/umount $maindir/mnt

## Duplicate the boot sector .iso file for bios/efi hybrid setup

echo "Duplicating the bootsector of the ISO image"
/bin/dd if=iso/firmware-"$version"-amd64-netinst.iso bs=512 count=1 of=cd/isolinux/isohdpfx.bin >/dev/null 2>&1

## Check / Copy the preseed configs into the .iso root

if [ ! -f "preseed/preseed.cfg" ]; then
	echo "preseed/preseed.cfg is missing: Copy a working preseed.cfg for legacy installs to ${maindir}/preseed/preseed.cfg and re-run the script"
	exit 1
fi

if [ ! -f "preseed/preseed-efi.cfg" ]; then
	echo "preseed/preseed-efi.cfg is missing: Copy a working preseed-efi.cfg for EFI installs to ${maindir}/preseed/preseed-efi.cfg and re-run the script"
	exit 1
fi

echo "Copying the preseed configs to their destination"
cp preseed/preseed.cfg cd/preseed.cfg
cp preseed/preseed-efi.cfg cd/preseed-efi.cfg

## Append the preseed config location for EFI to the grub.cfg

echo "Appending the preseed-efi.cfg to the GRUB auto install kernel line"
sed -i 's/auto\=true.*/auto\=true priority\=critical vga\=788 preseed\/file\=\/cdrom\/preseed-efi.cfg --/g' $maindir/cd/boot/grub/grub.cfg

## Set the preseed config for BIOS to the isolinux/txt.cfg

echo "Set a default config that loads the preseed.cfg for BIOS/Legacy installs"
cat > cd/isolinux/txt.cfg <<EOF
default install
label install
        menu label ^Automatic Preseed Install
        menu default
        kernel /install.amd/vmlinuz
        append auto=true priority=critical vga=788 initrd=/install.amd/initrd.gz preseed/file=/cdrom/preseed.cfg
label ia-install
        menu label ^Interactive Install
        menu default
        kernel /install.amd/vmlinuz
        append vga=788 initrd=/install.amd/initrd.gz --- quiet
EOF

## Create new md5 sums of the files

echo "Creating a new md5 checksum list after the changes"
cd cd
md5sum `find -follow -type f 2>/dev/null` > md5sum.txt
cd ..

## Create the hybrid .iso

echo "Creating the new ISO image"
iso_label=DEBIAN"${strippedversion}"EFIP
xorriso -as mkisofs \
       -iso-level 3 \
       -full-iso9660-filenames \
       -volid "${iso_label}" \
       -eltorito-boot isolinux/isolinux.bin \
       -eltorito-catalog isolinux/boot.cat \
       -no-emul-boot -boot-load-size 4 -boot-info-table \
       -isohybrid-mbr cd/isolinux/isohdpfx.bin \
       -eltorito-alt-boot \
       -e boot/grub/efi.img \
       -no-emul-boot -isohybrid-gpt-basdat \
       -output iso/debian-"${strippedversion}"-preseed.iso \
       ./cd >/dev/null 2>&1

xorrisoreturn=$?

if [[ $xorrisoreturn -ne 0 ]]; then
	echo "Error writing debian-"${strippedversion}"-preseed.iso"
	exit 1
else
	echo Debian "$version" AMD64 netinst BIOS/EFI iso with integrated preseed configs is created in "${maindir}"/iso/debian-"${strippedversion}"-preseed.iso
	exit 0
fi
