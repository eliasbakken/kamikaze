#!/bin/sh -e
#
# Copyright (c) 2014 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

u_boot_release="v2015.01"

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

export HOME=/home/${rfs_username}
export USER=${rfs_username}
export USERNAME=${rfs_username}

#echo "env: [`env`]"

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

setup_system () {
	#For when sed/grep/etc just gets way to complex...
	cd /
	if [ -f /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff ] ; then
		if [ -f /usr/bin/patch ] ; then
			echo "Patching: /etc/profile"
			patch -p1 < /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff
		fi
	fi

	if [ -f /opt/scripts/boot/am335x_evm.sh ] ; then
		if [ -f /lib/systemd/system/serial-getty@.service ] ; then
			cp /lib/systemd/system/serial-getty@.service /etc/systemd/system/serial-getty@ttyGS0.service
			ln -s /etc/systemd/system/serial-getty@ttyGS0.service /etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service

			echo "" >> /etc/securetty
			echo "#USB Gadget Serial Port" >> /etc/securetty
			echo "ttyGS0" >> /etc/securetty
		fi
	fi
}



install_pip_pkgs () {
	if [ -f /usr/bin/pip ] ; then
		echo "Installing pip packages"
		#Fixed in git, however not pushed to pip yet...(use git and install)
		#libpython2.7-dev
		#pip install Adafruit_BBIO

		git_repo="https://github.com/adafruit/adafruit-beaglebone-io-python.git"
		git_target_dir="/opt/source/adafruit-beaglebone-io-python"
		git_clone
		if [ -f ${git_target_dir}/.git/config ] ; then
			cd ${git_target_dir}/
			python setup.py install
		fi
	fi
}

install_git_repos () {
	git_repo="https://github.com/prpplague/fb-test-app.git"
	git_target_dir="/opt/source/fb-test-app"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ -f /usr/bin/make ] ; then
			make
		fi
	fi

	git_repo="https://github.com/alexanderhiam/PyBBIO.git"
	git_target_dir="/opt/source/PyBBIO"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ -f /usr/bin/dtc ] ; then
			sed -i "s/PLATFORM = ''/PLATFORM = 'BeagleBone >=3.8'/g" setup.py
			python setup.py install
		fi
	fi

	git_repo="https://github.com/RobertCNelson/dtb-rebuilder.git"
	git_branch="3.14-ti"
	git_target_dir="/opt/source/dtb-${git_branch}"
	git_clone_branch

	git_repo="git://git.ti.com/pru-software-support-package/pru-software-support-package.git"
	git_target_dir="/opt/source/pru-software-support-package"
	git_clone
}

other_source_links () {
	rcn_https="https://raw.githubusercontent.com/RobertCNelson/Bootloader-Builder/master/patches"

	mkdir -p /opt/source/u-boot_${u_boot_release}/
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-am335x_evm-uEnv.txt-bootz-n-fixes.patch
	wget --directory-prefix="/opt/source/u-boot_${u_boot_release}/" ${rcn_https}/${u_boot_release}/0001-beagle_x15-uEnv.txt-bootz-n-fixes.patch

	echo "u-boot_${u_boot_release} : /opt/source/u-boot_${u_boot_release}" >> /opt/source/list.txt
}

unsecure_root () {
	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
	sed -i -e 's:'$root_password'::g' /etc/shadow

	if [ -f /etc/ssh/sshd_config ] ; then
		#Make ssh root@beaglebone work..
		sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
		sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
		#Starting with Jessie:
		sed -i -e 's:PermitRootLogin without-password:PermitRootLogin yes:g' /etc/ssh/sshd_config
	fi

	if [ -f /etc/sudoers ] ; then
		#Don't require password for sudo access
		echo "${rfs_username}  ALL=NOPASSWD: ALL" >>/etc/sudoers
	fi
}



install_adafruit(){
	cd /usr/src/
	wget https://github.com/eliasbakken/adafruit-beaglebone-io-python/archive/master.tar.gz
	mv master.tar.gz Adafruit_BBIO.tar.gz
	tar xf Adafruit_BBIO.tar.gz
	cd adafruit-beaglebone-io-python-master
	python setup.py install
}

todo () {
	#stuff i need to package in repos.rcn-ee.com
	#
	cd /
	if [ ! -f /etc/Wireless/RT2870STA/RT2870STA.dat ] ; then
		mkdir -p /etc/Wireless/RT2870STA/
		cd /etc/Wireless/RT2870STA/
		wget https://raw.githubusercontent.com/rcn-ee/mt7601u/master/src/RT2870STA.dat
		cd /
	fi
	if [ ! -f /etc/modules-load.d/mt7601.conf ] ; then
		echo "mt7601Usta" > /etc/modules-load.d/mt7601.conf
	fi

	# Make i2c load at boot
	echo "i2c-dev" >> /etc/modules

	# Fix the perl langyage bug
	echo "export LC_ALL=C" >> /etc/profile

	# Make sure depmod -a is run on first boot
	echo "#!/bin/bash" 				  > /etc/init.d/first_boot
	echo "#Script run on first boot "		 >> /etc/init.d/first_boot
	echo "sleep 10" 				 >> /etc/init.d/first_boot
	echo "depmod -a" 				 >> /etc/init.d/first_boot
	echo "systemctl restart pvrsrv" 		 >> /etc/init.d/first_boot
	echo "systemctl restart toggle" 		 >> /etc/init.d/first_boot
	chmod +x /etc/init.d/first_boot

	# Make systemd script
	echo "[Unit]" 					  > /lib/systemd/system/first-boot.service
	echo "Description=depmod -a on first run"	 >> /lib/systemd/system/first-boot.service
	echo ""	 					 >> /lib/systemd/system/first-boot.service
	echo "[Service]"				 >> /lib/systemd/system/first-boot.service
	echo "ExecStart=/etc/init.d/first_boot"		 >> /lib/systemd/system/first-boot.service
	echo "ExecStartPost=/bin/systemctl mask first-boot" >> /lib/systemd/system/first-boot.service
 	echo ""						 >> /lib/systemd/system/first-boot.service
	echo "[Install]"				 >> /lib/systemd/system/first-boot.service
	echo "WantedBy=multi-user.target"		 >> /lib/systemd/system/first-boot.service

	if [ ! -f /etc/systemd/system/multi-user.target.wants/first-boot.service ] ; then
		ln -s /lib/systemd/system/first-boot.service /etc/systemd/system/multi-user.target.wants/first-boot.service
	fi

	# Make folder for octo
	mkdir -p /home/octo
	mkdir -p "/home/octo/.octoprint"
	chown -R octo:octo "/home/octo/.octoprint"
	
	# Fix permissions for STL upload folder
	chown octo:octo /usr/share/models
	chmod 777 /usr/share/models
	
	# Make config file for Octoprint
	echo "cura:"					 > "/home/octo/.octoprint/config.yaml"
	echo "  config: /etc/cura/printer.ini"		>> "/home/octo/.octoprint/config.yaml"
	echo "  enabled: true" 				>> "/home/octo/.octoprint/config.yaml"
	echo "  path: /usr/share/cura/cura.sh"		>> "/home/octo/.octoprint/config.yaml"
	echo "folder:"					>> "/home/octo/.octoprint/config.yaml"
	echo "  uploads: /usr/share/models"		>> "/home/octo/.octoprint/config.yaml"
	echo "serial:"					>> "/home/octo/.octoprint/config.yaml"
	echo "  additionalPorts:"			>> "/home/octo/.octoprint/config.yaml"
	echo "    - /dev/octoprint_1"			>> "/home/octo/.octoprint/config.yaml"
	echo "  baudrate: 115200"			>> "/home/octo/.octoprint/config.yaml"
	echo "  port: /dev/octoprint_1"			>> "/home/octo/.octoprint/config.yaml"

	chown octo:octo "/home/octo/.octoprint/config.yaml"

	# Remove local repo from hosts	
	sed -i "s/10.24.2.241 feeds.thing-printer.com//" /etc/hosts
}


is_this_qemu

setup_system
#if [ -f /usr/bin/git ] ; then
#	install_git_repos
#fi
other_source_links
unsecure_root

install_adafruit

todo



