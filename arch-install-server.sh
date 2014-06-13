#!/usr/bin/env bash
### installation process ####

DISK='/dev/sda'
FQDN='omv'
KEYMAP='fr-latin9'
LANGUAGE='fr_FR.UTF-8'
PASSWORD_ROOT=$(/usr/bin/openssl passwd -crypt 'PASSWORD_ROOT')
PASSWORD_USER=$(/usr/bin/openssl passwd -crypt 'PASSWORD_USER')
TIMEZONE='CET'
FONT='Lat2-Terminus16'

CONFIG_SCRIPT='/usr/local/bin/arch-install.sh'
ROOT_PARTITION="${DISK}1"
HOME_PARTITION="${DISK}2"
TARGET_ROOT_DIR='/mnt'
TARGET_HOME_DIR='/mnt/home'


### language ###

echo "==> loading FRENCH layout, changing the font"
/usr/bin/loadkeys ${KEYMAP}
/usr/bin/setfont ${FONT}

echo "==> changing the language for the install process"
echo "==> ATTENTION EXPORT COMMAND!!!"
/usr/bin/sed -i 's/#${LANGUAGE}/${LANGUAGE}/' /etc/locale.gen
/usr/bin/locale-gen
export LANG=${LANGUAGE}

### prepare the shorage drive ###

echo "==>1 destroy GPT and MBR data structure"
/usr/bin/sgdisk --zap-all ${DISK}
/usr/bin/sleep 5

echo "==>2 and clearing partition table on ${DISK}"
/usr/bin/dd if=/dev/zero of=${DISK} bs=512 count=2048
/usr/bin/wipefs --all ${DISK}
/usr/bin/sleep 5


echo "==>3 creating 2 partitions : 100 GB for / and the remaining for /home"
cat <<EOF | fdisk ${DISK}
n
p
1

+100G

n
p
2



w
EOF
/usr/bin/sleep 5



echo "==> creating / and /home filesystem"
/usr/bin/mkfs.ext4 ${DISK}1
/usr/bin/sleep 5
/usr/bin/mkfs.ext4 ${DISK}2
/usr/bin/sleep 5

echo "==> mounting ${ROOT_PARTITION} to ${TARGET_ROOT_DIR}"
/usr/bin/mount ${ROOT_PARTITION} ${TARGET_ROOT_DIR}

echo "==> creating ${TARGET_HOME_DIR}"
/usr/bin/mkdir ${TARGET_HOME_DIR}

echo "==> mounting ${HOME_PARTITION} to ${TARGET_HOME_DIR}"
/usr/bin/mount ${HOME_PARTITION} ${TARGET_HOME_DIR}

echo "==> if '0', alignement OK (sda, / and /home)"
/usr/bin/blockdev --getalignoff ${DISK}
/usr/bin/blockdev --getalignoff ${ROOT_PARTITION}
/usr/bin/blockdev --getalignoff ${HOME_PARTITION}
/usr/bin/sleep 5
  
### editing the mirror list ###

echo "==> editing the mirrorlist"
/usr/bin/pacman -Sy --noconfirm reflector git
/usr/bin/reflector -l 50 -p http --sort rate --save /etc/pacman.d/mirrorlist

### base system installation ###

echo '==> bootstrapping the base and base-devel installation'
/usr/bin/pacstrap ${TARGET_ROOT_DIR} base base-devel

### fstab generation ###
echo '==> generating the filesystem table'
/usr/bin/genfstab -U -p ${TARGET_ROOT_DIR} >> "${TARGET_ROOT_DIR}/etc/fstab"

### grub installation ###
/usr/bin/arch-chroot ${TARGET_ROOT_DIR} pacman -S --noconfirm grub openssh vim wget
/usr/bin/arch-chroot ${TARGET_ROOT_DIR} grub-install --target=i386-pc --recheck ${DISK}
/usr/bin/arch-chroot ${TARGET_ROOT_DIR} grub-mkconfig -o /boot/grub/grub.cfg
/usr/bin/sleep 5

echo '################# TIME TO CUSTOMIZE !!!! ##################'
echo '################# TIME TO CUSTOMIZE !!!! ##################'
echo '################# TIME TO CUSTOMIZE !!!! ##################'

echo '==> generating the system configuration script'
/usr/bin/install --mode=0755 /dev/null "${TARGET_ROOT_DIR}${CONFIG_SCRIPT}"

cat <<-EOF > "${TARGET_ROOT_DIR}${CONFIG_SCRIPT}"
	echo '${FQDN}' > /etc/hostname
	/usr/bin/ln -s /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
	echo 'KEYMAP=${KEYMAP}' > /etc/vconsole.conf
	echo 'FONT=${FONT}'
	/usr/bin/sed -i 's/#${LANGUAGE}/${LANGUAGE}/' /etc/locale.gen
	/usr/bin/locale-gen
	/usr/bin/mkinitcpio -p linux
	/usr/bin/usermod --password ${PASSWORD_ROOT} root
	# https://wiki.archlinux.org/index.php/Network_Configuration#Device_names
	/usr/bin/ln -s /dev/null /etc/udev/rules.d/80-net-name-slot.rules
	/usr/bin/ln -s '/usr/lib/systemd/system/dhcpcd@.service' '/etc/systemd/system/multi-user.target.wants/dhcpcd@eth0.service'
	/usr/bin/sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
    /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg 
	/usr/bin/systemctl enable sshd.service
	
	/usr/bin/sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers



	# tien-specific configuration
	/usr/bin/useradd --password ${PASSWORD_USER} --comment 'omv-server' --create-home --gid users -G wheel omv


	# Install yaourt
	curl -O https://aur.archlinux.org/packages/pa/package-query/package-query.tar.gz
	tar xvf package-query.tar.gz
	cd package-query
	makepkg -si --asroot --noconfirm
	cd ..
	curl -O https://aur.archlinux.org/packages/ya/yaourt/yaourt.tar.gz
	tar xvf yaourt.tar.gz
	cd yaourt
	makepkg -si --asroot --noconfirm
	cd ..
	rm -rf yaourt* package-query*

	# activate dhcpcd
    /usr/bin/systemctl enable dhcpcd

    
    ### git and .vimrc ###
    pacman -S --noconfirm git ctags
    git clone git://github.com/amix/vimrc.git /home/tien/.vim_runtime
    /home/tien/.vim_runtime/install_awesome_vimrc.sh
    rm -rf /home/tien/.vim_runtime

    ### graphical user ### 

	/usr/bin/pacman -Scc --noconfirm
EOF

echo '==> entering chroot and configuring system'
/usr/bin/arch-chroot ${TARGET_ROOT_DIR} ${CONFIG_SCRIPT}
rm "${TARGET_ROOT_DIR}${CONFIG_SCRIPT}"

echo '==> installation complete!'
/usr/bin/sleep 3
/usr/bin/umount ${TARGET_ROOT_DIR}
/usr/bin/systemctl reboot

