#!/bin/bash
#
# JMR-Pi   - Copyright Matthew Macdonald-Wallace 2012
# JMR-Pi 2 - Copyright Tim Watson 2015

## DOWNLOAD the various packages we need
JMRI_URL=$(curl -s http://jmri.org/releaselist -o - | tr '\n' ' ' | cut -d ":" -f 5,6 | cut -d " " -f 2 | cut -d '"' -f 2)
JMRI_PACKAGE_NAME=$(curl -s http://jmri.org/releaselist -o - | tr '\n' ' ' | cut -d ":" -f 6 | cut -d "/" -f 8)
WORKING_DIR=$(pwd)

function warning()
{
  echo "WARNING: $1"
}

function error()
{
  echo "ERROR: $1"
  exit 1
}

# CREATE the DOWNLOADS dir and get the latest stable version of JMRI
mkdir jmri_downloads
cd jmri_downloads
if [ -f $JMRI_PACKAGE_NAME ]
then
  echo -e "Package already downloading, skipping this step..."
else
  echo "Downloading latest production release from $JMRI_URL to $JMRI_PACKAGE_NAME"
  wget -O $JMRI_PACKAGE_NAME "$JMRI_URL"
fi
if [ $? -ne 0 ]
then
  error "Failed to download JMRI sources."
  exit 1
fi

## MOVE JMRI into the /opt folder
echo "Unpacking the source into /opt"
cd /opt
tar -zxf $WORKING_DIR/jmri_downloads/$JMRI_PACKAGE_NAME 
if [ $? -ne 0 ]
then
  error "Failed to unpack JMRI sources into /opt"
fi

## Installing the correct java with txrx library:
#apt-get -y install oracle-java7-jdk librxtx-java xrdp
#if [ $? -ne 0 ]
#then
#  error "Failed to install JAVA"
#fi

#create 2 pwd groups for our user to live in:
groupadd -r autologin
groupadd -r nopasswdlogin

# create the jmri user that we will run as:
#useradd -mG autologin,nopasswdlogin,adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,netdev,input -s /bin/bash jmri
useradd -m -s /bin/bash -G adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,netdev,input jmri
echo -e "jmri:trains" | (sudo chpasswd)

gpasswd -a jmri autologin
gpasswd -a jmri nopasswdlogin

#sed '2 i auth sufficient pam_succeed_if.so user ingroup nopasswdlogin' /etc/pam.d/lightdm

#pam.d needs to know to auto load the nopasswdlogin group
echo "auth        sufficient  pam_succeed_if.so user ingroup nopasswdlogin" | sudo tee -a /etc/pam.d/lightdm


# install SAMBA and configure a file server:
apt-get -y install samba samba-common-bin
if [ $? -ne 0 ]
then
  error "Failed to install samba"
fi

cp $WORKING_DIR/scripts/samba/smb.conf /etc/samba/smb.conf
if [ $? -ne 0 ]
then
  error "Failed to copy samba config file"
fi
service samba restart
mkdir /home/jmri/.jmri
chown -Rf jmri: /home/jmri/.jmri

# add the user to the Samba database
echo -e "trains\ntrains" | (smbpasswd -a -s jmri)

# copy the files to the correct location and set permissions:
cp $WORKING_DIR/scripts/lightdm/lightdm.conf /etc/lightdm/lightdm.conf
cp $WORKING_DIR/scripts/init.d/tightvncserver /etc/init.d/tightvncserver
if [ ! -f /home/jmri/.jmri/PanelProConfig2.xml ]
then
  cp $WORKING_DIR/scripts/jmri/PanelProConfig2.xml /home/jmri/.jmri/PanelProConfig2.xml
  ln -s /home/jmri/.jmri/JmriFacelessConfig3.xml /home/jmri/.jmri/PanelProConfig2.xml
fi

chmod 755 /etc/init.d/tightvncserver
#chmod +x /etc/init.d/vncboot
mkdir -p /home/jmri/.config/lxsession/LXDE-pi
echo '@/opt/JMRI/PanelPro' >> /home/jmri/.config/lxsession/LXDE-pi/autostart
chown -Rf jmri: /home/jmri
chown -Rf jmri: /opt/JMRI

# start the services:
/etc/init.d/tightvncserver start
if [ $? -ne 0 ]
 then
  warning "VNC server failed to start"
fi
#
# add the vnc service to start at boot
update-rc.d tightvncserver defaults
# or might need to use this instead
# update-rc.d /etc/init.d/tightvncserver defaults


# get the current ip addresses
ip=$(hostname -I)
echo -e "hostname -I" > test.log
# echo the details:
echo "---- Your JMRI server has been installed ----"
echo "To connect through VNC or Remote Desktop use the following IP/port: $ip:5901"
echo "JMRI will take several minutes to start the first time it is run."
echo "Your config files should be available by browsing SAMBA to \\$ip\\JMRI\\"

exit 0
