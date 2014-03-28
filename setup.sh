#!/bin/bash
#
# JMR-Pi - Copyright Matthew Macdonald-Wallace 2012

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

# create the downloads dir and get the latest stable version of JMRI
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

echo "Unpacking the source into /opt"
cd /opt
tar -zxf $WORKING_DIR/jmri_downloads/$JMRI_PACKAGE_NAME 
if [ $? -ne 0 ]
then
  error "Failed to unpack JMRI sources into /opt"
fi

## installing the correct java txrx library:
apt-get -y install oracle-java7-jdk librxtx-java xrdp
if [ $? -ne 0 ]
then
  error "Failed to install dependencies"
fi


####### Uncomment this if you've changed the script to use a much older version that still requires the RXTX Hack
#cd /opt/JMRI/lib/linux/armv5
#mv librxtxSerial.so librxtxSerial.so.jmri
#ln -s /usr/lib/jni/librxtxSerial.so

# create the jmri user that we will run as:
useradd -m -s /bin/bash -G adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,netdev,input jmri
echo -e "jmri:trains" | (chpasswd)

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
# cp $WORKING_DIR/scripts/init.d/vncserver /etc/init.d/vncserver
if [ ! -f /home/jmri/.jmri/PanelProConfig2.xml ]
then
  cp $WORKING_DIR/scripts/jmri/PanelProConfig2.xml /home/jmri/.jmri/PanelProConfig2.xml
  ln -s /home/jmri/.jmri/JmriFacelessConfig3.xml /home/jmri/.jmri/PanelProConfig2.xml
fi
#chmod +x /etc/init.d/vncserver
mkdir -p /home/jmri/.config/lxsession/LXDE
echo '@/opt/JMRI/PanelPro' >> /home/jmri/.config/lxsession/LXDE/autostart
chown -Rf jmri: /home/jmri
chown -Rf jmri: /opt/JMRI

# start the services:
#/etc/init.d/vncserver start
#if [ $? -ne 0 ]
#then
#  warning "VNC server failed to start"
#fi
#
# add the vnc service to start at boot
#update-rc.d vncserver defaults

# get the current ip addresses
ip=$(hostname -I)
echo -e " hostname -I" > test.log
# echo the details:
echo "### Your JMRI server is ready ###"
echo "VNC/RDP IPs: $ip Port: 5901"
echo "JMRI will take several minutes to start the first time it is run."
echo "Your config files should be available by browsing to \\$IPADDRESS\\JMRI\\"

exit 0
