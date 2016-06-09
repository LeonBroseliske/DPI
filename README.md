## Debian Preseed Iso creation script

Integrates preseed configs for both legacy as EFI installs into the latest stable Debian netinstall ISO (including firmware for certain NICs) to automate your installs.

Tested on Debian Jessie and on Ubuntu LTS.

## Preseed configs

For both type of installs, an example config is included. More info on preseeding:

https://www.debian.org/releases/jessie/amd64/apb.html.en

## Using the script

By default the script uses /var/local/dpi as the working dir, this can be changed in the 'settings' section.

The initial run of the script creates the different subdirs the script uses and then exits on the missing preseed.cfg.

* Copy your legacy install preseed config to preseed/preseed.cfg
* Copy your EFI install preseed config to preseed/preseed-efi.cfg
* When using the example configs, don't forget to at least change/create a hash for the root password

Now run the script again and it will integrate those configs into the new ISO that's created in the iso/ dir.

## Using the ISO to start an automated install

# Starting the install from BIOS/Legacy mode
* Boot the image
* Select 'Automatic Preseed Install'

# Starting the install from EFI mode
* Boot the image
* Select 'Advanced'
* Select 'Automated Install'
