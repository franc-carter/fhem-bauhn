fhem-bauhn
==========

An fhem driver for the Bauhn/Aldi/Orvibo wi-fi power point

Have a look here for background

https://discuss.ninjablocks.com/t/aldi-remote-controlled-power-points-5-july-2014/1793

Put the following in your fhem config file to use it

    define NAME Bauhn XX:XX:XX:XX:XX:XX
    attr NAME setList off on

where NAME is the name you wish to call the device and XX:XX:XX:XX:XX:XX is the MAC address of the device
