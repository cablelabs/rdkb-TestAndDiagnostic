#This script is used to enable / start the speedtest tool

#!/bin/sh
echo "Enabling / Starting speedtest..." > /dev/console
. /etc/device.properties
if [ "$BOX_TYPE" = XB3 ]
then
  echo "Executing run_speedtest.sh for xb3" > /dev/console
  rpcclient $ATOM_ARPING_IP "/etc/speedtest/run_speedtest.sh"
elif [ "$BOX_TYPE" = XB6 ]
then
  echo "Executing run_speedtest.sh for xb6" > /dev/console
  sh /etc/speedtest/run_speedtest.sh
else
  echo "Unsupported device model" > /dev/console
fi
