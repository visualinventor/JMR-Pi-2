#!/bin/bash
#
# JMR-Pi   -  Copyright Matthew Macdonald-Wallace 2012
# JMR-Pi 2 - Copyright Tim Watson 2015-2016
# All JMRI sources are owned/copyrighted by JMRI

#Set the working dir up high
WORKING_DIR=$(pwd)

# Installing wi-fi hotspot library
apt-get -y install hostapd udhcpd
if [ $? -ne 0 ]
then
  error "Failed to install wi-fi hot spot library"
fi

cp $WORKING_DIR/conf/hostapd/udhcpd.conf /etc/udhcpd.conf
if [ $? -ne 0 ]
then
  error "Failed to copy udhcpd config file"
fi

# We need to comment out the no dhcp option
sed -e '/DHCPD_ENABLED/ s/^#*/#/' -i /etc/default/udhcpd

#Next we need to set a static IP address since we're now a hotspot
 ifconfig wlan0 192.168.10.1

#Add our new static ip address to the pi
echo "iface wlan0 inet static" >> /etc/network/interfaces
echo "address 192.168.10.1" >> /etc/network/interfaces
echo "netmask 255.255.255.0" >> /etc/network/interfaces

# We need to comment out theese if they exist
sed -e '/allow-hotplug/ s/^#*/#/' -i /etc/network/interfaces
sed -e '/wpa-roam/ s/^#*/#/' -i /etc/network/interfaces
sed -e '/iface default inet manual/ s/^#*/#/' -i /etc/network/interfaces

cp $WORKING_DIR/conf/hostapd/hostapd.conf  /etc/hostapd/hostapd.conf
if [ $? -ne 0 ]
then
  error "Failed to copy hostapd config file"
fi

# Make sure the DAEMON is set 
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd

# Start the nat ip forwarding
sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# Setup IP tables
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE 
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
 
 # Save IP tables
sh -c "iptables-save > /etc/iptables.ipv4.nat"

echo "up iptables-restore < /etc/iptables.ipv4.nat" >> /etc/network/interfaces

# Start them up
service hostapd start
service udhcpd start

update-rc.d hostapd enable
update-rc.d udhcpd enable

#### End wi-fi hotspot setup

# change name from default hostname
echo '127.0.0.1 jmripi2' >> /etc/hosts

## Installing a JMRI 4 or greater compatible java with rxtx library:
apt-get -y install oracle-java8-jdk librxtx-java xrdp
if [ $? -ne 0 ]
then
  error "Failed to install JAVA"
fi

## DOWNLOAD the various JMRI packages we need
JMRI_URL=$(curl -s http://jmri.org/releaselist -o - | tr '\n' ' ' | cut -d ":" -f 5,6 | cut -d " " -f 2 | cut -d '"' -f 2)
JMRI_PACKAGE_NAME=$(curl -s http://jmri.org/releaselist -o - | tr '\n' ' ' | cut -d ":" -f 6 | cut -d "/" -f 8)

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


#create 2 pwd groups for our jmri user to live in:
groupadd -r autologin
groupadd -r nopasswdlogin

# create the jmri user that we will run as:
#useradd -mG autologin,nopasswdlogin,adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,netdev,input -s /bin/bash jmri
useradd -m -s /bin/bash -G adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,netdev,input jmri
echo -e "jmri:trains" | (sudo chpasswd)

gpasswd -a jmri autologin
gpasswd -a jmri nopasswdlogin

#pam.d needs to know to auto load the nopasswdlogin group - https://wiki.archlinux.org/index.php/LightDM
echo "auth        sufficient  pam_succeed_if.so user ingroup nopasswdlogin" | sudo tee -a /etc/pam.d/lightdm


# install SAMBA and configure a file server:
apt-get -y install samba samba-common-bin
if [ $? -ne 0 ]
then
  error "Failed to install samba"
fi

cp $WORKING_DIR/conf/samba/smb.conf /etc/samba/smb.conf
if [ $? -ne 0 ]
then
  error "Failed to copy samba config file"
fi
service samba restart

mkdir /home/jmri/.jmri
chown -Rf jmri: /home/jmri/.jmri

# add the user to the Samba database
echo -e "trains\ntrains" | (smbpasswd -a -s jmri)

#get tightvncserver
apt-get -y install tightvncserver

# copy the files to the correct location and set permissions:
cp $WORKING_DIR/conf/lightdm/lightdm.conf /etc/lightdm/lightdm.conf
cp $WORKING_DIR/conf/init.d/tightvncserver /etc/init.d/tightvncserver

if [ ! -f /home/jmri/.jmri/PanelProConfig2.xml ]
then
  cp $WORKING_DIR/confs/jmri/PanelProConfig2.xml /home/jmri/.jmri/PanelProConfig2.xml
  ln -s /home/jmri/.jmri/JmriFacelessConfig3.xml /home/jmri/.jmri/PanelProConfig2.xml
fi

chmod +x /etc/init.d/tightvncserver

mkdir -p /home/jmri/.config/lxsession/LXDE-pi
# To run a more limited version of JMRI (Faceless) comment out the below line and uncomment the one below it
echo '@/opt/JMRI/PanelPro' >> /home/jmri/.config/lxsession/LXDE-pi/autostart
#echo '@/opt/JMRI/JmriFaceless' >> /home/jmri/.config/lxsession/LXDE-pi/autostart
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

# get the current ip addresses
ip=$(hostname -I)
echo -e "hostname -I" > test.log
# echo the details:
echo "---- Your JMRI server has been installed ----"
echo "To connect through VNC or Remote Desktop use the following IP/port: $ip:5901"
echo "JMRI will take several minutes to start the first time it is run."
echo "Your config files should be available by browsing SAMBA to \\$ip\\JMRI\\"

exit 0
