fhem-bauhn
==========

An fhem driver for the Bauhn/Aldi/Orvibo wi-fi power point

Have a look here for background

https://discuss.ninjablocks.com/t/aldi-remote-controlled-power-points-5-july-2014/1793

Put the following in your fhem config file to use it

   define Study_Heater Bauhn AC:CF:23:24:11:80
   attr Study_Heater setList off on
