JMRPi2
=========

This repo contains scripts to configure JMRI on a Raspberry PI 2 for use in the computer control of model railroad layouts.

To get the code, log onto your R-PI, start a terminal if you do not have one already and run the following commands:

```bash
git clone https://github.com/visualinventor/JMRPi2
```
```bash
cd JMRPi2
```
```bash
sudo ./setup.sh
```

This will:

  * Checkout this repository
  * Change to the checked-out code
  * Run the installation script
  * Sets up your wifi stick to be wireless access point
  * Sets a static ip address to the wifi hotspot
  * Create a dedicated JMRI user
  * Start a VNC/remote desktop server
  * Automatically Launch JMRI

About halfway through you will be asked About "setting a password for your desktops"
Type in whatever password you would like but remember it because this will be the password you use to VNC into your RPi. 
The password for the JMRI user (should you need to connect to the R-Pi and run commands on its behalf!) is "trains".

The message that is generated at the end of the script gives you an IP Address and a Port Number to use to log in via VNC and start a remote desktop session.  Once you have done this, you should see JMRI starting up.

It's highly recommended to disconnect your wired ethernet connection AFTER the install is done so withrottle doesn't get confused as to which IP address it needs to use.
