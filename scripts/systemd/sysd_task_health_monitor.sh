#! /bin/sh
#######################################################################################
# If not stated otherwise in this file or this component's Licenses.txt file the
# following copyright and licenses apply:

#  Copyright 2018 RDK Management

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#######################################################################################

UTOPIA_PATH="/etc/utopia/service.d"
TAD_PATH="/usr/ccsp/tad"
RDKLOGGER_PATH="/rdklogger"
ADVSEC_PATH="/usr/ccsp/advsec/usr/libexec/advsec.sh"

if [ -f /etc/device.properties ]
then
    source /etc/device.properties
fi
source /etc/log_timestamp.sh

ping_failed=0
ping_success=0
SyseventdCrashed="/rdklogs/syseventd_crashed"
PING_PATH="/usr/sbin"
WAN_INTERFACE="erouter0"
source $UTOPIA_PATH/log_env_var.sh

exec 3>&1 4>&2 >>$SELFHEALFILE 2>&1

source $TAD_PATH/corrective_action.sh

if [ -f $ADVSEC_PATH ]
then
    source $ADVSEC_PATH
fi
rebootDeviceNeeded=0

brlan1_firewall="/tmp/brlan1_firewall_rule_validated"
LIGHTTPD_CONF="/var/lighttpd.conf"

PSM_PID=`pidof PsmSsp`
	if [ "$PSM_PID" != "" ]; then
		psm_name=`dmcli eRT getv com.cisco.spvtg.ccsp.psm.Name`
		psm_name_timeout=`echo $psm_name | grep "CCSP_ERR_TIMEOUT"`
		psm_name_notexist=`echo $psm_name | grep "CCSP_ERR_NOT_EXIST"`
		if [ "$psm_name_timeout" != "" ] || [ "$psm_name_notexist" != "" ]; then
			psm_health=`dmcli eRT getv com.cisco.spvtg.ccsp.psm.Health`
			psm_health_timeout=`echo $psm_health | grep "CCSP_ERR_TIMEOUT"`
			psm_health_notexist=`echo $psm_health | grep "CCSP_ERR_NOT_EXIST"`
			if [ "$psm_health_timeout" != "" ] || [ "$psm_health_notexist" != "" ]; then
				echo "RDKB_PROCESS_CRASHED : PSM_process is in hung state, need restart"
				systemctl restart PsmSsp.service
			fi
		fi
	fi
	HOMESEC_PID=`pidof CcspHomeSecurity`
	if [ "$HOMESEC_PID" = "" ]; then
		echo "[`getDateTime`] RDKB_PROCESS_CRASHED : HomeSecurity process is not running, need restart"
		resetNeeded "" CcspHomeSecurity 
	fi

	DEVICE_FINGERPRINT_VALUE=`syscfg get Advsecurity_DeviceFingerPrint`
	if [ "$DEVICE_FINGERPRINT_VALUE" = "1" ] ; then
	        DEVICE_FINGERPRINT_ENABLE=true
	else
	        DEVICE_FINGERPRINT_ENABLE=false
	fi

	advsec_bridge_mode=`syscfg get bridge_mode`
	if [ "$DEVICE_FINGERPRINT_ENABLE" = "true" ] && [ "$advsec_bridge_mode" != "2" ]; then

		if [ -f $ADVSEC_PATH ]
		then
			if [ ! -f $ADVSEC_INITIALIZING ]
			then   
				ADV_AG_PID=`advsec_is_alive agent`
				if [ "$ADV_AG_PID" = "" ] ; then
					echo "[`getDateTime`] RDKB_PROCESS_CRASHED : AdvSecurity Agent process is not running, need restart"
					resetNeeded advsec_bin AdvSecurityAgent
				fi
				ADV_DHCP_PID=`advsec_is_alive dhcpcap`
				if [ "$ADV_DHCP_PID" = "" ] ; then
					echo "[`getDateTime`] RDKB_PROCESS_CRASHED : AdvSecurity Dhcpcap process is not running, need restart"
					resetNeeded advsec_bin AdvSecurityDhcp
				fi
				if [ ! -f "$DAEMONS_HIBERNATING" ] ; then
					ADV_DNS_PID=`advsec_is_alive dnscap`
					if [ "$ADV_DNS_PID" = "" ] ; then
						echo "[`getDateTime`] RDKB_PROCESS_CRASHED : AdvSecurity Dnscap process is not running, need restart"
						resetNeeded advsec_bin AdvSecurityDns
					fi
					ADV_MDNS_PID=`advsec_is_alive mdnscap`
					if [ "$ADV_MDNS_PID" = "" ] ; then
						echo "[`getDateTime`] RDKB_PROCESS_CRASHED : AdvSecurity Mdnscap process is not running, need restart"
						resetNeeded advsec_bin AdvSecurityMdns
					fi
					ADV_P0F_PID=`advsec_is_alive p0f`
					if [ "$ADV_P0F_PID" = "" ] ; then
						echo "[`getDateTime`] RDKB_PROCESS_CRASHED : AdvSecurity PoF process is not running, need restart"
						resetNeeded advsec_bin AdvSecurityPof
					fi
				fi
				ADV_SCAN_PID=`advsec_is_alive scannerd`
				if [ "$ADV_SCAN_PID" = "" ] ; then
					echo "[`getDateTime`] RDKB_PROCESS_CRASHED : AdvSecurity Scanner process is not running, need restart"
					resetNeeded advsec_bin AdvSecurityScanner
				fi
				if [ -e ${SAFEBRO_ENABLE} ] ; then
					ADV_SB_PID=`advsec_is_alive threatd`
					if [ "$ADV_SB_PID" = "" ] ; then
						echo "RDKB_PROCESS_CRASHED : AdvSecurity Threat process is not running, need restart"
						resetNeeded advsec_bin AdvSecurityThreat
					fi
				fi
				if [ -e ${SOFTFLOWD_ENABLE} ] ; then
					ADV_SF_PID=`advsec_is_alive softflowd`
					if [ "$ADV_SF_PID" = "" ] ; then
						echo "RDKB_PROCESS_CRASHED : AdvSecurity Softflowd process is not running, need restart"
						resetNeeded advsec_bin AdvSecuritySoftflowd
					fi
				fi
			fi
		fi
	fi
				
	HOTSPOT_ENABLE=`dmcli eRT getv Device.DeviceInfo.X_COMCAST_COM_xfinitywifiEnable | grep value | cut -f3 -d : | cut -f2 -d" "`
	if [ "$HOTSPOT_ENABLE" = "true" ]
	then
	
		DHCP_ARP_PID=`pidof hotspot_arpd`
        if [ "$DHCP_ARP_PID" = "" ] && [ -f /tmp/hotspot_arpd_up ]; then
			echo "[`getDateTime`] RDKB_PROCESS_CRASHED : DhcpArp_process is not running, need restart"
			resetNeeded "" hotspot_arpd 
   	fi
	fi

	#Checking dropbear PID 
	DROPBEAR_PID=`pidof dropbear`
	if [ "$DROPBEAR_PID" = "" ]; then
		echo "[`getDateTime`] RDKB_PROCESS_CRASHED : dropbear_process is not running, restarting it"
		sh /etc/utopia/service.d/service_sshd.sh sshd-restart &
	fi	

	# Checking lighttpd PID
	LIGHTTPD_PID=`pidof lighttpd`
	if [ "$LIGHTTPD_PID" = "" ]; then
		isPortKilled=`netstat -an | grep 21515`
		if [ "$isPortKilled" != "" ]
		then
		    echo "[`getDateTime`] Port 21515 is still alive. Killing processes associated to 21515"
		    fuser -k 21515/tcp
		fi
		echo "[`getDateTime`] RDKB_PROCESS_CRASHED : lighttpd is not running, restarting it"
		sh /etc/webgui.sh
	fi
# Checking syseventd PID
 	SYSEVENT_PID=`pidof syseventd`
	if [ "$SYSEVENT_PID" == "" ]
	then
		if [ ! -f "$SyseventdCrashed"  ]
		then
			echo "[`getDateTime`] [RDKB_PROCESS_CRASHED] : syseventd is crashed, need to reboot the device in maintanance window." 
			touch $SyseventdCrashed
		fi
		rebootDeviceNeeded=1
	fi
	
	# Checking whether brlan0 is created properly , if not recreate it
	lanSelfheal=`sysevent get lan_selfheal`
	echo "[`getDateTime`] [RDKB_SELFHEAL] : Value of lanSelfheal : $lanSelfheal"
	if [ "$lanSelfheal" != "done" ]
	then
      # Check device is in router mode
      # Get from syscfg instead of dmcli for performance reasons
			check_device_in_bridge_mode=`syscfg get bridge_mode`
			if [ "$check_device_in_bridge_mode" == "0" ]
			then
				check_if_brlan0_created=`ifconfig | grep brlan0`
				check_if_brlan0_up=`ifconfig brlan0 | grep UP`
				check_if_brlan0_hasip=`ifconfig brlan0 | grep "inet addr"`
				if [ "$check_if_brlan0_created" = "" ] || [ "$check_if_brlan0_up" = "" ] || [ "$check_if_brlan0_hasip" = "" ]
				then
					echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : brlan0 is not completely up, setting event to recreate vlan and brlan0 interface"
					logNetworkInfo

					ipv4_status=`sysevent get ipv4_4-status`
					lan_status=`sysevent get lan-status`

					if [ "$lan_status" != "started" ]
					then
						if [ "$ipv4_status" = "" ] || [ "$ipv4_status" = "down" ]
						then
							echo "[`getDateTime`] [RDKB_SELFHEAL] : ipv4_4-status is not set or lan is not started, setting lan-start event"
							sysevent set lan-start
							sleep 5
						fi
					fi

					if [ "$check_if_brlan0_created" = "" ]; then	
						/etc/utopia/registration.d/02_multinet restart
					fi

					sysevent set multinet-down 1
					sleep 5
					sysevent set multinet-up 1
					sleep 30
					sysevent set lan_selfheal done
				fi

			fi
		else

		echo "[`getDateTime`] [RDKB_SELFHEAL] : brlan0 already restarted. Not restarting again"
	fi
			
	# Checking whether brlan1 interface is created properly

	l3netRestart=`sysevent get l3net_selfheal`
	echo "[`getDateTime`] [RDKB_SELFHEAL] : Value of l3net_selfheal : $l3netRestart"

	if [ "$l3netRestart" != "done" ]
	then

		check_if_brlan1_created=`ifconfig | grep brlan1`
		check_if_brlan1_up=`ifconfig brlan1 | grep UP`
		check_if_brlan1_hasip=`ifconfig brlan1 | grep "inet addr"`
	
		if [ "$check_if_brlan1_created" = "" ] || [ "$check_if_brlan1_up" = "" ] || [ "$check_if_brlan1_hasip" = "" ]
        	then
	       		echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : brlan1 is not completely up, setting event to recreate vlan and brlan1 interface"

			ipv5_status=`sysevent get ipv4_5-status`
			lan_l3net=`sysevent get homesecurity_lan_l3net`

			if [ "$lan_l3net" != "" ]
			then
				if [ "$ipv5_status" = "" ] || [ "$ipv5_status" = "down" ]
				then
					echo "[`getDateTime`] [RDKB_SELFHEAL] : ipv5_4-status is not set , setting event to create homesecurity lan"
					sysevent set ipv4-up $lan_l3net
					sleep 5
				fi
			fi

			if [ "$check_if_brlan1_created" = "" ]; then
				/etc/utopia/registration.d/02_multinet restart
			fi

			sysevent set multinet-down 2
			sleep 5
			sysevent set multinet-up 2
			sleep 10
			sysevent set l3net_selfheal done
		fi
	else
		echo "[`getDateTime`] [RDKB_SELFHEAL] : brlan1 already restarted. Not restarting again"
	fi

	# Test to make sure that if mesh is enabled the backhaul tunnels are attached to the bridges
	MESH_ENABLE=`dmcli eRT getv Device.DeviceInfo.X_RDKCENTRAL-COM_xOpsDeviceMgmt.Mesh.Enable | grep value | cut -f3 -d : | cut -f2 -d" "`
	if [ "$MESH_ENABLE" = "true" ]
	then
	   echo "[RDKB_SELFHEAL] : Mesh is enabled, test if tunnels are attached to bridges"
	
	   # Fetch mesh tunnels from the brlan0 bridge if they exist
	   brctl0_ifaces=`brctl show brlan0 | egrep "pgd"` 
	   br0_ifaces=`ifconfig | egrep "^pgd" | egrep "\.100" | awk '{print $1}'`
	
	   for ifn in $br0_ifaces; do
	      brFound="false"
	
	      for br in $brctl0_ifaces; do
	         if [ "$br" == "$ifn" ]; then
	            brFound="true"
	         fi
	      done
	      if [ "$brFound" == "false" ]; then
	         echo "[RDKB_SELFHEAL] : Mesh bridge $ifn missing, adding iface to brlan0"
	         brctl addif brlan0 $ifn;
	      fi
	   done
	
	   # Fetch mesh tunnels from the brlan1 bridge if they exist
	   brctl1_ifaces=`brctl show brlan1 | egrep "pgd"` 
	   br1_ifaces=`ifconfig | egrep "^pgd" | egrep "\.101" | awk '{print $1}'`
	
	   for ifn in $br1_ifaces; do
	      brFound="false"
	
	      for br in $brctl1_ifaces; do
	         if [ "$br" == "$ifn" ]; then
	            brFound="true"
	         fi
	      done
	      if [ "$brFound" == "false" ]; then
	         echo "[RDKB_SELFHEAL] : Mesh bridge $ifn missing, adding iface to brlan1"
	         brctl addif brlan1 $ifn;
	      fi
	   done
	fi

    #Selfheal will run after 15mins of bootup, then by now the WIFI initialization must have 
    #completed, so if still wifi_initilization not done, we have to recover the WIFI
    #Restart the WIFI if initialization is not done with in 15mins of poweron.
	SSID_DISABLED=0
	BR_MODE=0
    if [ -f "/tmp/wifi_initialized" ]
    then
    echo "[RDKB_SELFHEAL] : WiFi Initialization done"
	ssidEnable=`dmcli eRT getv Device.WiFi.SSID.2.Enable`
	ssidExecution=`echo $ssidEnable | grep "Execution succeed"`
	if [ "$ssidExecution" != "" ]
	then
	   isEnabled=`echo $ssidEnable | grep "false"`
	   if [ "$isEnabled" != "" ]
	   then
		 SSID_DISABLED=1
		 echo "[`getDateTime`] [RDKB_SELFHEAL] : SSID 5GHZ is disabled"
	   fi
	else
	   destinationError=`echo $ssidEnable | grep "Can't find destination component"`
       if [ "$destinationError" != "" ]
       then
            echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : Parameter cannot be found on WiFi subsystem"
       else
            echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : Something went wrong while checking 5G Enable"
            echo "$ssidEnable"
       fi            
	fi
    else
        echo "[RDKB_PLATFORM_ERROR] : WiFi initialization not done"
        if [[ "$BOX_TYPE" = "XB6" && "$MANUFACTURE" = "Technicolor" ]]; then
            if [ -f "/tmp/.qtn_ready" ]
            then
                echo "[RDKB_PLATFORM_ERROR] : restarting the CcspWifiSsp"
                systemctl stop ccspwifiagent
                systemctl start ccspwifiagent
            fi
        fi
    fi

# RDKB-6895
        isBridging=`syscfg get bridge_mode`
        if [ "$isBridging" != "0" ]

           then
               BR_MODE=1
               echo "[`getDateTime`] [RDKB_SELFHEAL] : Device in bridge mode"
           fi

        #check for PandM response
        bridgeMode=`dmcli eRT getv Device.X_CISCO_COM_DeviceControl.LanManagementEntry.1.LanMode`
        bridgeSucceed=`echo $bridgeMode | grep "Execution succeed"`
        if [ "$bridgeSucceed" == "" ]
        then
            echo "[RDKB_SELFHEAL_DEBUG] : bridge mode = $bridgeMode"
            serialNumber=`dmcli eRT getv Device.DeviceInfo.SerialNumber`
            echo "[RDKB_SELFHEAL_DEBUG] : SerialNumber = $serialNumber"
            modelName=`dmcli eRT getv Device.DeviceInfo.ModelName`
            echo "[RDKB_SELFHEAL_DEBUG] : modelName = $modelName"

            pandm_timeout=`echo $bridgeMode | grep "CCSP_ERR_TIMEOUT"`
            pandm_notexist=`echo $bridgeMode | grep "CCSP_ERR_NOT_EXIST"`
            if [ "$pandm_timeout" != "" ] || [ "$pandm_notexist" != "" ]
            then
                echo "[RDKB_PLATFORM_ERROR] : pandm parameter timed out or failed to return"
                cr_query=`dmcli eRT getv com.cisco.spvtg.ccsp.pam.Name`
                cr_timeout=`echo $cr_query | grep "CCSP_ERR_TIMEOUT"`
                cr_pam_notexist=`echo $cr_query | grep "CCSP_ERR_NOT_EXIST"`
                if [ "$cr_timeout" != "" ] || [ "$cr_pam_notexist" != "" ]
                then
                        echo "[RDKB_PLATFORM_ERROR] : pandm process is not responding. Restarting it"

                        rm -rf /tmp/pam_initialized
                        systemctl restart CcspPandMSsp.service
                fi
            fi
        fi

	# If bridge mode is not set and WiFI is not disabled by user,
	# check the status of SSID
	if [ $BR_MODE -eq 0 ] && [ $SSID_DISABLED -eq 0 ]
	then           
	ssidStatus_5=`dmcli eRT getv Device.WiFi.SSID.2.Status`
		isExecutionSucceed=`echo $ssidStatus_5 | grep "Execution succeed"`
		if [ "$isExecutionSucceed" != "" ]
		then       

			isUp=`echo $ssidStatus_5 | grep "Up"`
			if [ "$isUp" = "" ]
			then
			   # We need to verify if it was a dmcli crash or is WiFi really down
			   isDown=`echo $ssidStatus_5 | grep "Down"`
			   if [ "$isDown" != "" ]; then
				  echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : 5G private SSID (ath1) is off."
			   else
				  echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : Something went wrong while checking 5G status."
                  echo "$ssidStatus_5"
			   fi
			fi
		else
		   echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : wifi agent is off while checking 5G status."
           echo "$ssidStatus_5"
		fi
	fi

	# Check the status if 2.4GHz Wifi SSID
	SSID_DISABLED_2G=0
	ssidEnable_2=`dmcli eRT getv Device.WiFi.SSID.1.Enable`
	ssidExecution_2=`echo $ssidEnable_2 | grep "Execution succeed"`

	if [ "$ssidExecution_2" != "" ]
	then
		isEnabled_2=`echo $ssidEnable_2 | grep "false"`
		if [ "$isEnabled_2" != "" ]
		then
		   SSID_DISABLED_2G=1
		   echo "[`getDateTime`] [RDKB_SELFHEAL] : SSID 2.4GHZ is disabled"
		fi
	else
		echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : wifi agent is off while checking 2.4G Enable"
		echo "$ssidEnable_2"
	fi

	# If bridge mode is not set and WiFI is not disabled by user,
	# check the status of SSID
	if [ $BR_MODE -eq 0 ] && [ $SSID_DISABLED_2G -eq 0 ]
	then
		ssidStatus_2=`dmcli eRT getv Device.WiFi.SSID.1.Status`
		isExecutionSucceed_2=`echo $ssidStatus_2 | grep "Execution succeed"`
		if [ "$isExecutionSucceed_2" != "" ]
		then       

			isUp=`echo $ssidStatus_2 | grep "Up"`
			if [ "$isUp" = "" ]
			then
				# We need to verify if it was a dmcli crash or is WiFi really down
				isDown=`echo $ssidStatus_2 | grep "Down"`
				if [ "$isDown" != "" ]; then
					echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : 2.4G private SSID (ath0) is off."
				else
					echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : Something went wrong while checking 2.4G status."
					echo "$ssidStatus_2"
				fi
			fi
		else
		   echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : wifi agent is off while checking 2.4G status."
		   echo "$ssidStatus_2"
		fi
	fi
        
	FIREWALL_ENABLED=`syscfg get firewall_enabled`

	echo "[`getDateTime`] [RDKB_SELFHEAL] : BRIDGE_MODE is $BR_MODE"
    echo "[`getDateTime`] [RDKB_SELFHEAL] : FIREWALL_ENABLED is $FIREWALL_ENABLED"

	if [ $BR_MODE -eq 0 ] 
	then
		iptables-save -t nat | grep "A PREROUTING -i"
		if [ $? == 1 ]; then
		echo "[`getDateTime`] [RDKB_PLATFORM_ERROR] : iptable corrupted."
		#sysevent set firewall-restart
		fi
     fi

	if [ $BR_MODE -eq 0 ] && [ ! -f "$brlan1_firewall" ]
	then
		firewall_rules=`iptables-save`
		check_if_brlan1=`echo $firewall_rules | grep brlan1`
		if [ "$check_if_brlan1" == "" ]; then
			echo "[RDKB_PLATFORM_ERROR]:brlan1_firewall_rules_missing,restarting firewall"
			sysevent set firewall-restart
		fi
		touch $brlan1_firewall
         fi

#Logging to check the DHCP range corruption
    lan_ipaddr=`syscfg get lan_ipaddr`
    lan_netmask=`syscfg get lan_netmask`
    echo "[`getDateTime`]DHCPCORRUPT_TRACE:lan_ipaddr=$lan_ipaddr,lan_netmask=$lan_netmask"

    lost_and_found_enable=`syscfg get lost_and_found_enable`
    echo "[`getDateTime`]DHCPCORRUPT_TRACE:lost_and_found_enable=$lost_and_found_enable"
    if [ "$lost_and_found_enable" == "true" ]
    then
        iot_ifname=`syscfg get iot_ifname`
        iot_dhcp_start=`syscfg get iot_dhcp_start`
        iot_dhcp_end=`syscfg get iot_dhcp_end`
        iot_netmask=`syscfg get iot_netmask`
        echo "[`getDateTime`]DHCPCORRUPT_TRACE:iot_ifname=$iot_ifname "
        echo "[`getDateTime`]DHCPCORRUPT_TRACE:iot_dhcp_start=$iot_dhcp_start,iot_dhcp_end=$iot_dhcp_end,iot_netmask=$iot_netmask"
    fi

#Checking whether dnsmasq is running or not
   DNS_PID=`pidof dnsmasq`
   if [ "$DNS_PID" == "" ]
   then
		 echo "[`getDateTime`] [RDKB_SELFHEAL] : dnsmasq is not running"   
   else
	     brlan1up=`cat /var/dnsmasq.conf | grep brlan1`
	     brlan0up=`cat /var/dnsmasq.conf | grep brlan0`


	     IsAnyOneInfFailtoUp=0	

	     if [ $BR_MODE -eq 0 ]
	     then
			if [ "$brlan0up" == "" ]
			then
			    echo "[`getDateTime`] [RDKB_SELFHEAL] : brlan0 info is not availble in dnsmasq.conf"
			    IsAnyOneInfFailtoUp=1
			fi
	     fi

	     if [ "$brlan1up" == "" ]
	     then
	         echo "[`getDateTime`] [RDKB_SELFHEAL] : brlan1 info is not availble in dnsmasq.conf"
			 IsAnyOneInfFailtoUp=1
	     fi



	     if [ ! -f /tmp/dnsmasq_restarted_via_selfheal ] 
	     then
		     if [ $IsAnyOneInfFailtoUp -eq 1 ]
		     then
				 touch /tmp/dnsmasq_restarted_via_selfheal

		         echo "[`getDateTime`] [RDKB_SELFHEAL] : dnsmasq.conf is."   
			 	 echo "`cat /var/dnsmasq.conf`"

				 echo "[`getDateTime`] [RDKB_SELFHEAL] : Setting an event to restart dnsmasq"
		         sysevent set dhcp_server-stop
		         sysevent set dhcp_server-start
		     fi
	     fi
	
	checkIfDnsmasqIsZombie=`ps | grep dnsmasq | grep "Z" | awk '{ print $1 }'`
	if [ "$checkIfDnsmasqIsZombie" != "" ] ; then
		for zombiepid in $checkIfDnsmasqIsZombie
		do
			confirmZombie=`grep "State:" /proc/$zombiepid/status | grep -i "zombie"`
			if [ "$confirmZombie" != "" ] ; then
				echo "[`getDateTime`] [RDKB_SELFHEAL] : Zombie instance of dnsmasq is present, restarting dnsmasq"
				kill -9 `pidof dnsmasq`
				sysevent set dhcp_server-stop
				sysevent set dhcp_server-start
				break
			fi
		done
	fi

   fi

#Checking dibbler server is running or not RDKB_10683
	DIBBLER_PID=`pidof dibbler-server`
	if [ "$DIBBLER_PID" = "" ]; then

		DHCPV6C_ENABLED=`sysevent get dhcpv6c_enabled`
		if [ "$BR_MODE" == "0" ] && [ "$DHCPV6C_ENABLED" == "1" ]; then
			#ARRISXB6-7776 .. check if IANAEnable is set to 0
			IANAEnable=`syscfg show | grep dhcpv6spool00::IANAEnable | cut -d "=" -f2`
			if [ "$IANAEnable" = "0" ] ; then
				echo "[`getDateTime`] IANAEnable disabled, enable and restart dhcp6 client and dibbler"
				syscfg set dhcpv6spool00::IANAEnable 1
				syscfg commit
				sleep 2
				#need to restart dhcp client to generate dibbler conf
				sh $DHCPV6_HANDLER disable
				sleep 2
				sh $DHCPV6_HANDLER enable
			else
				
				echo "[`getDateTime`] RDKB_PROCESS_CRASHED : Dibbler is not running, restarting the dibbler"
			
				if [ -f "/etc/dibbler/server.conf" ]
				then
					dibbler-server stop
					sleep 2
					dibbler-server start
				else
					echo "[`getDateTime`] RDKB_PROCESS_CRASHED : Server.conf file not present, Cannot restart dibbler"
				fi
			fi
		fi
	fi

#Checking the zebra is running or not
	ZEBRA_PID=`pidof zebra`
	if [ "$ZEBRA_PID" = "" ]; then
		if [ "$BR_MODE" == "0" ]; then

			echo "[`getDateTime`] RDKB_PROCESS_CRASHED : zebra is not running, restarting the zebra"
			/etc/utopia/registration.d/20_routing restart
			sysevent set zebra-restart
		fi
	fi

	
	#All CCSP Processes Now running on Single Processor. Add those Processes to Test & Diagnostic 
	# Checking for WAN_INTERFACE ipv6 address
	DHCPV6_ERROR_FILE="/tmp/.dhcpv6SolicitLoopError"
	WAN_STATUS=`sysevent get wan-status`
	WAN_IPv4_Addr=`ifconfig $WAN_INTERFACE | grep inet | grep -v inet6`
	DHCPV6_HANDLER="/etc/utopia/service.d/service_dhcpv6_client.sh"

if [ "$WAN_STATUS" != "started" ]
then
	echo "[`getDateTime`] WAN_STATUS : wan-status is $WAN_STATUS"
fi

	if [ -f "$DHCPV6_ERROR_FILE" ] && [ "$WAN_STATUS" = "started" ] && [ "$WAN_IPv4_Addr" != "" ]
	then
		          isIPv6=`ifconfig $WAN_INTERFACE | grep inet6 | grep "Scope:Global"`
			echo "isIPv6 = $isIPv6"
	        	 if [ "$isIPv6" == "" ]
			 then
				echo "[`getDateTime`] [RDKB_SELFHEAL] : $DHCPV6_ERROR_FILE file present and $WAN_INTERFACE ipv6 address is empty, restarting ti_dhcp6c"
				rm -rf $DHCPV6_ERROR_FILE
				sh $DHCPV6_HANDLER disable
				sleep 2
				sh $DHCPV6_HANDLER enable
	           	fi 
	fi
	
	if [ "$WAN_STATUS" = "started" ];then
		wan_dhcp_client_v4=1
		wan_dhcp_client_v6=1

		if [[ "$BOX_TYPE" = "XB6" && "$MANUFACTURE" = "Technicolor" || "$BOX_TYPE" = "TCCBR" ]]; then
			check_wan_dhcp_client_v4=`ps w | grep udhcpc | grep erouter`
			check_wan_dhcp_client_v6=`ps w | grep dibbler-client | grep -v grep`
		else
			dhcp_cli_output=`ps w | grep ti_ | grep erouter0`
			check_wan_dhcp_client_v4=`echo $dhcp_cli_output | grep ti_udhcpc`
			check_wan_dhcp_client_v6=`echo $dhcp_cli_output | grep ti_dhcp6c`
		fi

		if [ "x$check_wan_dhcp_client_v4" = "x" ]; then
			echo "[`getDateTime`] RDKB_PROCESS_CRASHED : DHCP Client for v4 is not running, need restart "
			wan_dhcp_client_v4=0
		fi

		if [ "x$check_wan_dhcp_client_v6" = "x" ]; then
			echo "[`getDateTime`] RDKB_PROCESS_CRASHED : DHCP Client for v6 is not running, need restart"
			wan_dhcp_client_v6=0
		fi

		DHCP_STATUS=`dmcli eRT getv Device.DHCPv4.Client.1.DHCPStatus | grep value | cut -f3 -d : | cut -f2 -d" "`

		if [ "$DHCP_STATUS" != "Bound" ] ; then
			if [ $wan_dhcp_client_v4 -eq 0 ] || [ $wan_dhcp_client_v6 -eq 0 ]; then
				echo "[`getDateTime`] DHCP_CLIENT : DHCPStatus is $DHCP_STATUS, restarting WAN"
				sh /etc/utopia/service.d/service_wan.sh wan-stop
				sh /etc/utopia/service.d/service_wan.sh wan-start
				wan_dhcp_client_v4=1
				wan_dhcp_client_v6=1
			fi
		fi

		if [ $wan_dhcp_client_v4 -eq 0 ];
		then
			if [[ "$BOX_TYPE" = "XB6" && "$MANUFACTURE" = "Technicolor" || "$BOX_TYPE" = "TCCBR" ]]; then
				V4_EXEC_CMD="/sbin/udhcpc -i erouter0 -p /tmp/udhcpc.erouter0.pid -s /etc/udhcpc.script"
			else
				DHCPC_PID_FILE="/var/run/eRT_ti_udhcpc.pid"
				V4_EXEC_CMD="ti_udhcpc -plugin /lib/libert_dhcpv4_plugin.so -i $WAN_INTERFACE -H DocsisGateway -p $DHCPC_PID_FILE -B -b 1"
			fi

			echo "[`getDateTime`] DHCP_CLIENT : Restarting DHCP Client for v4"
			eval "$V4_EXEC_CMD"
			sleep 5
			wan_dhcp_client_v4=1
		fi

		if [ $wan_dhcp_client_v6 -eq 0 ];
		then
			echo "[`getDateTime`] DHCP_CLIENT : Restarting DHCP Client for v6"
			if [[ "$BOX_TYPE" = "XB6" && "$MANUFACTURE" = "Technicolor" || "$BOX_TYPE" = "TCCBR" ]]; then
				/etc/dibbler/dibbler-init.sh
				sleep 2
				/usr/sbin/dibbler-client start
			else
				sh $DHCPV6_HANDLER disable
				sleep 2
				sh $DHCPV6_HANDLER enable
			fi
			wan_dhcp_client_v6=1
		fi

	fi
	
	if [ -f $PING_PATH/ping_peer ]
	then
	## Check Peer ip is accessible
	loop=1
		while [ "$loop" -le 3 ]
		do
			PING_RES=`ping_peer`
			CHECK_PING_RES=`echo $PING_RES | grep "packet loss" | cut -d"," -f3 | cut -d"%" -f1`

			if [ "$CHECK_PING_RES" != "" ]
			then
				if [ "$CHECK_PING_RES" -ne 100 ] 
				then
					ping_success=1
					echo "[`getDateTime`] RDKB_SELFHEAL : Ping to Peer IP is success"
					break
				else
					ping_failed=1
				fi
			else
				ping_failed=1
			fi

			if [ "$ping_failed" -eq 1 ] && [ "$loop" -lt 3 ]
			then
				echo "[`getDateTime`] RDKB_SELFHEAL : Ping to Peer IP failed in iteration $loop"
			else
				echo "[`getDateTime`] RDKB_SELFHEAL : Ping to Peer IP failed after iteration $loop also ,rebooting the device"
				echo "[`getDateTime`] RDKB_REBOOT : Peer is not up ,Rebooting device "
				echo "[`getDateTime`] Setting Last reboot reason Peer_down"
                reason="Peer_down"
                rebootCount=1
                rebootNeeded RM "" $reason $rebootCount

			fi
			loop=$((loop+1))
			sleep 5
		done
	else
	   echo "[`getDateTime`] RDKB_SELFHEAL : ping_peer command not found"
	fi
	
	if [ -f $PING_PATH/arping_peer ]
	then
		$PING_PATH/arping_peer
	else
	   echo "[`getDateTime`] RDKB_SELFHEAL : arping_peer command not found"
	fi
	
	if [ "$rebootDeviceNeeded" -eq 1 ]
	then
	
		if [ "$UTC_ENABLE" == "true" ]
		then
			cur_hr=`LTime H`
			cur_min=`LTime M`
		else
			cur_hr=`date +"%H"`
			cur_min=`date +"%M"`
		fi
		
		if [ $cur_hr -ge 02 ] && [ $cur_hr -le 03 ]
		then
			if [ $cur_hr -eq 03 ] && [ $cur_min -ne 00 ]
			then
				echo "Maintanance window for the current day is over , unit will be rebooted in next Maintanance window "
			else
			#Check if we have already flagged reboot is needed
				if [ ! -e $FLAG_REBOOT ]
				then
					if [ "$rebootNeededforbrlan1" -eq 1 ]
					then
						echo "rebootNeededforbrlan1"
						echo "[`getDateTime`] RDKB_REBOOT : brlan1 interface is not up, rebooting the device."
						echo "[`getDateTime`] Setting Last reboot reason"
						dmcli eRT setv Device.DeviceInfo.X_RDKCENTRAL-COM_LastRebootReason string brlan1_down
						echo "[`getDateTime`] SET succeeded"
						sh /etc/calc_random_time_to_reboot_dev.sh "" &
					else 
						echo "rebootDeviceNeeded"
						sh /etc/calc_random_time_to_reboot_dev.sh "" &
					fi
					touch $FLAG_REBOOT
				else
					echo "Already waiting for reboot"
				fi					
			fi
		fi
	fi
