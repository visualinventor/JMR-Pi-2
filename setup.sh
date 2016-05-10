#!/bin/bash
#
# JMRPi2 -   Copyright Tim Watson 2015-2016
# JMR-Pi -   Copyright Matthew Macdonald-Wallace 2012
# All JMRI sources are owned/copyrighted by JMRI

# Set these to be anything you like
CUSTOM_USER="jmrpi2"
CUSTOM_PASSWORD="trains"
CUSTOM_HOSTNAME="jmrpi2"
STATIC_IP="192.168.10.1"
#REPO_NAME="JMRPi2"

##JMRI Parts
JMRI_DL_DIR="jmri_download"
JMRI_URL=$(curl -s http://jmri.org/releaselist -o - | tr '\n' ' ' | cut -d ":" -f 5,6 | cut -d " " -f 2 | cut -d '"' -f 2)
JMRI_PACKAGE_NAME=$(curl -s http://jmri.org/releaselist -o - | tr '\n' ' ' | cut -d ":" -f 6 | cut -d "/" -f 8)

#Set the working dir
WORKING_DIR=$(pwd)

# Make sure the pi has the most recent sources
echo "------------- Making sure your pi has the most recent sources"
apt-get update

# We need to set a static IP address since we're going to be a hotspot
echo "------------- Setting static IP address to $STATIC_IP"
ifconfig wlan0 $STATIC_IP

echo "------------- Backing up original Network Interfaces"
cp /etc/network/interfaces /etc/network/interfacesbackup
cp $WORKING_DIR/conf/network/interfaces /etc/network/interfaces

# Installing wi-fi hotspot library
echo "------------- Going to download and install the wifi hotspot and DHCP software"
apt-get -y install hostapd udhcpd
if [ $? -ne 0 ]
then
  error "Failed to install wi-fi hotspot and DHCP library"
fi

## BEGIN DHCP changes
echo "------------- Making DHCP changes"
cp $WORKING_DIR/conf/udhcpd/udhcpd.conf /etc/udhcpd.conf
if [ $? -ne 0 ]
then
  error "Failed to copy udhcpd config file"
fi

echo "opt router\t$STATIC_IP" >> /etc/udhcpd.conf

# We need to comment out the dhcp option
sed -e '/DHCPD_ENABLED/ s/^#*/#/' -i /etc/default/udhcpd

# With dhcpcd these are all we need for a static ip address
echo "interface wlan0" >> /etc/dhcpcd.conf
echo "static ip_address=$STATIC_IP/24" >> /etc/dhcpcd.conf
echo "static routers=$STATIC_IP" >> /etc/dhcpcd.conf
echo "static domain_name_servers=$STATIC_IP 8.8.8.8" >> /etc/dhcpcd.conf

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

echo "------------- Making sure DHCP starts after static IP"
cp $WORKING_DIR/conf/wlan/fixnet /etc/network/if-up.d/fixnet
chmod 755 /etc/network/if-up.d/fixnet

# Start them up
service hostapd start
service udhcpd start

update-rc.d hostapd defaults
update-rc.d udhcpd defaults

#### End wi-fi hotspot setup


# change name from default hostname
echo "------------- Setting host and hostname to $CUSTOM_HOSTNAME"
if grep raspberrypi /etc/hosts
then
    CURRENT_HOSTNAME=`cat /etc/hostname | tr -d " \t\n\r"`
    if [ $? -eq 0 ]; then
      echo $CUSTOM_HOSTNAME > /etc/hostname
      sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$CUSTOM_HOSTNAME/g" /etc/hosts
    fi
else
    echo "Looks like the hostname has been changed from the default skipping hostname change"
fi


## Installing a JMRI 4 or greater compatible java with rxtx library:
#echo "------------- Installing a JMRI 4 or greater compatible java with rxtx library"
#apt-get -y install oracle-java8-jdk librxtx-java xrdp
#if [ $? -ne 0 ]
#then
#  error "Failed to install JAVA"
#fi


echo "------------- Checking to see if we already downloaded JMRI"
if [ -d "$JMRI_DL_DIR" ]
then
  echo "The $JMRI_DL_DIR already exists ... moving on"
else
  mkdir $JMRI_DL_DIR
fi

cd $JMRI_DL_DIR

## DOWNLOAD the various JMRI packages we need
echo "------------- DOWNLOAD the various JMRI packages we need"
if [ -f $JMRI_PACKAGE_NAME ]
then
  echo -e "Package already downloading, skipping this step..."
else
  echo "Downloading latest JMRI production release from $JMRI_URL to $JMRI_DL_DIR/$JMRI_PACKAGE_NAME"
  wget -O $JMRI_PACKAGE_NAME "$JMRI_URL"
fi
if [ $? -ne 0 ]
then
  error "Failed to download JMRI sources."
  exit 1
fi

## MOVE JMRI into the /opt folder
echo "Unpacking the JMRI source into /opt"
cd /opt
tar -zxf $WORKING_DIR/$JMRI_DL_DIR/$JMRI_PACKAGE_NAME
if [ $? -ne 0 ]
then
  error "Failed to unpack JMRI sources into /opt"
fi


#create 2 pwd groups for our jmrpi2 user to live in:
groupadd -r autologin
groupadd -r nopasswdlogin

# create the jmri user that we will run as:
useradd -m -s /bin/bash -G adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,netdev,input $CUSTOM_USER
echo -e "$CUSTOM_USER:$CUSTOM_PASSWORD" | (sudo chpasswd)

gpasswd -a $CUSTOM_USER autologin
gpasswd -a $CUSTOM_USER nopasswdlogin

#pam.d needs to know to auto load the nopasswdlogin group - https://wiki.archlinux.org/index.php/LightDM
echo "auth        sufficient  pam_succeed_if.so user ingroup nopasswdlogin" | sudo tee -a /etc/pam.d/lightdm

# install SAMBA and configure a file server:
echo "------------- Install SAMBA and configure a file server"
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

# add the user to the Samba database
echo -e "$CUSTOM_PASSWORD\n$CUSTOM_PASSWORD" | (smbpasswd -a -s $CUSTOM_USER)

#get tightvncserver
apt-get -y install tightvncserver

# copy the files to the correct location and set permissions:
cp $WORKING_DIR/conf/lightdm/lightdm.conf /etc/lightdm/lightdm.conf
cp $WORKING_DIR/conf/init.d/tightvncserver /etc/init.d/tightvncserver

chmod +x /etc/init.d/tightvncserver

# start the services:
/etc/init.d/tightvncserver start
if [ $? -ne 0 ]
 then
  warning "VNC server failed to start"
fi

# add the vnc service to start at boot
update-rc.d tightvncserver defaults

## ---- Now we do our JMRI file shuffle
mkdir /home/$CUSTOM_USER/.jmri
chown -Rf $CUSTOM_USER: /home/$CUSTOM_USER/.jmri

mkdir -p /home/$CUSTOM_USER/.config/lxsession/LXDE-pi

# To run a more limited version of JMRI (Faceless) comment out the below line and uncomment the one below it
echo '@/opt/JMRI/PanelPro' >> /home/$CUSTOM_USER/.config/lxsession/LXDE-pi/autostart
#echo '@/opt/JMRI/JmriFaceless' >> /home/$CUSTOM_USER/.config/lxsession/LXDE-pi/autostart
chown -Rf $CUSTOM_USER: /home/$CUSTOM_USER
chown -Rf $CUSTOM_USER: /opt/JMRI


# get the current ip addresses
ip=$(hostname -I)
#echo -e "hostname -I" > test.log
# echo the details:
echo "---- Your Wireless Access point and JMRI server have been installed ----"
echo "JMRI will take several minutes to start the first time it is run."
echo "Once JMRI is started you must connect to the Raspberry Pi and finish setup INSIDE JMRI."
echo "Up to this point JMRI doesn't know your command station or connection method. YOU NEED TO SET THIS UP NEXT."
echo "To connect through VNC or Remote Desktop use the following IP/port: $ip:5901"
echo "Your JMRI config files will be available by browsing with SAMBA on a PC  to \\$ip\\JMRI\\ or via Macintosh $CUSTOM_HOSTNAME.local"

exit 0
