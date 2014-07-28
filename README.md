fhem-bauhn
==========

An fhem driver for the Bauhn/Aldi/Orvibo wi-fi power point

Have a look here for background

https://discuss.ninjablocks.com/t/aldi-remote-controlled-power-points-5-july-2014/1793

The driver is split in two pieces, a Bridge that does the network communication between fhem and the physical devices and a Device which represents the device specific information.

Put the following in your fhem config file to use it

    Define BRIDGE_NAME BauhnBridge

    define DEVICE_NAME BauhnDevice XX:XX:XX:XX:XX:XX
    attr DEVICE_NAME setList off on

where DEVICE_NAME is the name you wish to call the device and XX:XX:XX:XX:XX:XX is the MAC address of the device
