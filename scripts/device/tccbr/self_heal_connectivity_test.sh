#!/bin/sh
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
TAD_PATH="/usr/ccsp/tad/"
UTOPIA_PATH="/etc/utopia/service.d"

source $UTOPIA_PATH/log_env_var.sh

exec 3>&1 4>&2 >>$SELFHEALFILE 2>&1
rand_num_old=""
source $TAD_PATH/corrective_action.sh
source /etc/log_timestamp.sh
source /etc/device.properties

# Generate random time to start 
WAN_INTERFACE="erouter0"

calcRandom=1
ping4_server_num=0
ping6_server_num=0
ping4_success=0
ping6_success=0
ping4_failed=0
ping6_failed=0

getCorrectiveActionState() {
    Corrective_Action=`syscfg get ConnTest_CorrectiveAction`
    echo "$Corrective_Action"
}

calcRandTimetoStartPing()
{

    rand_min=0
    rand_sec=0

    # Calculate random min
    rand_min=`awk -v min=0 -v max=59 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`

    # Calculate random second
    rand_sec=`awk -v min=0 -v max=59 -v seed="$(date +%N)" 'BEGIN{srand(seed);print int(min+rand()*(max-min+1))}'`

    sec_to_sleep=$(($rand_min*60 + $rand_sec))
    sleep $sec_to_sleep; 
        
}

# A generic function which can be used for any URL parsing
removehttp()
{
	urlToCheck=$1
	haveHttp=`echo $urlToCheck | grep //`
	if [ "$haveHttp" != "" ]
	then
		url=`echo $urlToCheck | cut -f2 -d":" | cut -f3 -d"/"`
		echo $url
	else
		haveSlashAlone=`echo $urlToCheck | grep /`
		if [ "$haveSlashAlone" != "" ]
		then
			url=`echo $urlToCheck | cut -f1 -d"/"`
			echo $url
		else	
			echo $urlToCheck
		fi
	fi
}

runDNSPingTest() 
{
	DNS_PING_TEST_STATUS=`syscfg get selfheal_dns_pingtest_enable`
	
	if [ "$DNS_PING_TEST_STATUS" = "true" ]
	then
		urlToVerify=`syscfg get selfheal_dns_pingtest_url`
		
		if [ -z "$urlToVerify" ]
		then
			echo_t "DNS Response: DNS PING Test URL is empty"
			return
		fi

		DNS_PING_TEST_URL=`removehttp $urlToVerify`

		if [ "$DNS_PING_TEST_URL" = "" ]
		then
			echo_t "DNS Response: DNS PING Test URL is empty"
			return
		fi

		nslookup $DNS_PING_TEST_URL > /dev/null 2>&1
		RESPONSE=$?

		if [ $RESPONSE -eq 0 ]
		then
			echo_t "DNS Response: Got success response for this URL $DNS_PING_TEST_URL"
		else
			echo_t "DNS Response: fail to resolve this URL $DNS_PING_TEST_URL"

			if [ `getCorrectiveActionState` = "true" ]
			then
				echo_t "RDKB_SELFHEAL : Taking corrective action"
				resetNeeded "" PING
			fi
		fi
	fi
}

runPingTest()
{
	PING_PACKET_SIZE=`syscfg get selfheal_ping_DataBlockSize`
	PINGCOUNT=`syscfg get ConnTest_NumPingsPerServer`

	if [ "$PINGCOUNT" = "" ] 
	then
		PINGCOUNT=3
	fi

#	MINPINGSERVER=`syscfg get ConnTest_MinNumPingServer`

#	if [ "$MINPINGSERVER" = "" ] 
#	then
#		MINPINGSERVER=1
#	fi	

	RESWAITTIME=`syscfg get ConnTest_PingRespWaitTime`

	if [ "$RESWAITTIME" = "" ] 
	then
		RESWAITTIME=1000
	fi
	RESWAITTIME=$(($RESWAITTIME/1000))

	RESWAITTIME=$(($RESWAITTIME*$PINGCOUNT))


        IPv4_Gateway_addr=""
        IPv4_Gateway_addr=`dmcli eRT getv Device.DHCPv4.Client.1.IPRouters | grep "value:" | cut -d ":" -f 3 | tr -d ' '`

        IPv6_Gateway_addr=""
        erouterIP6=`ifconfig $WAN_INTERFACE | grep inet6 | grep Global | awk '{print $(NF-1)}' | cut -f1 -d:`

        if [ $erouterIP6 != "" ]
        then
           routeEntry=`ip -6 route list | grep $WAN_INTERFACE | grep $erouterIP6`
           IPv6_Gateway_addr=`echo $routeEntry | cut -f1 -d " "`
        fi

	if [ "$IPv4_Gateway_addr" != "" ]
	then
		PING_OUTPUT=`ping -I $WAN_INTERFACE -c $PINGCOUNT -w $RESWAITTIME $IPv4_Gateway_addr`
		output_ipv4=`echo $?` 
		CHECK_PACKET_RECEIVED=`echo $PING_OUTPUT | grep "packet loss" | cut -d"%" -f1 | awk '{print $NF}'`

		if [ "$CHECK_PACKET_RECEIVED" != "" ]
		then
			if [ "$CHECK_PACKET_RECEIVED" -ne 100 ] 
			then
				ping4_success=1
			else
				ping4_failed=1
			fi
		else
			ping4_failed=1
		fi
	fi

	if [ "$IPv6_Gateway_addr" != "" ]
	then
		PING_OUTPUT=`ping6 -I $WAN_INTERFACE -c $PINGCOUNT -w $RESWAITTIME $IPv6_Gateway_addr`
		output_ipv6=`echo $?` 
		CHECK_PACKET_RECEIVED=`echo $PING_OUTPUT | grep "packet loss" | cut -d"%" -f1 | awk '{print $NF}'`

		if [ "$CHECK_PACKET_RECEIVED" != "" ]
		then
			if [ "$CHECK_PACKET_RECEIVED" -ne 100 ] 
			then
				ping6_success=1
			else
				ping6_failed=1
			fi
		else
			ping6_failed=1
		fi
	fi

	if [ "$ping4_success" -ne 1 ] &&  [ "$ping6_success" -ne 1 ]
	then
		echo_t "RDKB_SELFHEAL : Ping to both IPv4 and IPv6 Gateway Address failed."
		echo "IPERROR_Ping: IP_Host=[$IPv4_Gateway_addr], Ping_Error = [$output_ipv4]"
		echo "IPERROR_Ping: IP_Host=[$IPv6_Gateway_addr], Ping_Error = [$output_ipv6]"		
		if [ `getCorrectiveActionState` = "true" ]
		then
			echo_t "RDKB_SELFHEAL : Taking corrective action"
			resetNeeded "" PING
		fi
	elif [ "$ping4_success" -ne 1 ]
	then
                if [ "$IPv4_Gateway_addr" != "" ]
                then
                   echo_t "RDKB_SELFHEAL : Ping to IPv4 Gateway Address failed."
                else
                   echo_t "RDKB_SELFHEAL : No IPv4 Gateway Address detected"
                fi

        	echo "IPERROR_Ping: IP_Host=[$IPv4_Gateway_addr], Ping_Error = [$output_ipv4]"

                if [ "$BOX_TYPE" = "XB3" ]
                then
                      dhcpStatus=`dmcli eRT getv Device.DHCPv4.Client.1.DHCPStatus | grep value | awk '{print $5}'`
                      wanIP=`ifconfig erouter0 | grep "inet addr" | cut -f2 -d: | cut -f1 -d" "`
                      if [ "$dhcpStatus" = "Rebinding" ] && [ "$wanIP" != "" ]
                      then
                          echo_t "EROUTER_DHCP_STATUS:Rebinding"
                      fi
                fi

		if [ `getCorrectiveActionState` = "true" ]
		then
			echo_t "RDKB_SELFHEAL : Taking corrective action"
			resetNeeded "" PING
		fi
	elif [ "$ping6_success" -ne 1 ]
	then
                if [ "$IPv6_Gateway_addr" != "" ]
                then
		            echo_t "RDKB_SELFHEAL : Ping to IPv6 Gateway Address are failed."
                else
                    echo_t "RDKB_SELFHEAL : No IPv6 Gateway Address detected"
                fi

		echo "IPERROR_Ping: IP_Host=[$IPv6_Gateway_addr], Ping_Error = [$output_ipv6]"	
		
		if [ `getCorrectiveActionState` = "true" ]
		then
			echo_t "RDKB_SELFHEAL : Taking corrective action"
			resetNeeded "" PING
		fi
	else
		echo_t "RDKB_SELFHEAL : GW IP Connectivity Test Successfull"
	fi	

	ping4_success=0
	ping4_failed=0
	ping6_success=0
	ping6_failed=0


	IPV4_SERVER_COUNT=`syscfg get Ipv4PingServer_Count`
	IPV6_SERVER_COUNT=`syscfg get Ipv6PingServer_Count`
	
	# Ping test for IPv4 Server 
	while [ "$ping4_server_num" -le "$IPV4_SERVER_COUNT" ] && [ "$IPV4_SERVER_COUNT" -ne 0 ]
	do

		ping4_server_num=$((ping4_server_num+1))
		PING_SERVER_IS=`syscfg get Ipv4_PingServer_$ping4_server_num`
		if [ "$PING_SERVER_IS" != "" ] && [ "$PING_SERVER_IS" != "0.0.0.0" ]
		then
			PING_OUTPUT=`ping -I $WAN_INTERFACE -c $PINGCOUNT -w $RESWAITTIME $PING_SERVER_IS`
			output_ping4server=`echo $?` 
			CHECK_PACKET_RECEIVED=`echo $PING_OUTPUT | grep "packet loss" | cut -d"%" -f1 | awk '{print $NF}'`
			if [ "$CHECK_PACKET_RECEIVED" != "" ]
			then
				if [ "$CHECK_PACKET_RECEIVED" -ne 100 ] 
				then
					ping4_success=1
				else
					ping4_failed=1
				fi
			else
				ping4_failed=1
			fi
			
			if [ "$ping4_failed" -eq 1 ];then
			   echo "IPERROR_Ping: IP_Host=[$PING_SERVER_IS], Ping_Error = [$output_ping4server]"
			   ping4_failed=0
			fi
		fi
	done

	# Ping test for IPv6 Server 
	while [ "$ping6_server_num" -le "$IPV6_SERVER_COUNT" ] && [ "$IPV6_SERVER_COUNT" -ne 0 ]
	do
		ping6_server_num=$((ping6_server_num+1))
		PING_SERVER_IS=`syscfg get Ipv6_PingServer_$ping6_server_num`
		if [ "$PING_SERVER_IS" != "" ] && [ "$PING_SERVER_IS" != "0000::0000" ]
		then
			PING_OUTPUT=`ping -I $WAN_INTERFACE -c $PINGCOUNT -w $RESWAITTIME $PING_SERVER_IS`
			output_ping6server=`echo $?`
			CHECK_PACKET_RECEIVED=`echo $PING_OUTPUT | grep "packet loss" | cut -d"%" -f1 | awk '{print $NF}'`
			if [ "$CHECK_PACKET_RECEIVED" != "" ]
			then
				if [ "$CHECK_PACKET_RECEIVED" -ne 100 ] 
				then
					ping6_success=1
				else
					ping6_failed=1
				fi
			else
				ping6_failed=1
			fi

			if [ "$ping6_failed" -eq 1 ];then
			   echo "IPERROR_Ping: IP_Host=[$PING_SERVER_IS], Ping_Error = [$output_ping6server]"
			   ping6_failed=0
			fi

		fi
	done

	if [ "$IPV4_SERVER_COUNT" -eq 0 ] ||  [ "$IPV6_SERVER_COUNT" -eq 0 ]
	then

			if [ "$IPV4_SERVER_COUNT" -eq 0 ] && [ "$IPV6_SERVER_COUNT" -eq 0 ]
			then
				echo_t "RDKB_SELFHEAL : Ping server lists are empty , not taking any corrective actions"				

			elif [ "$ping4_success" -ne 1 ] && [ "$IPV4_SERVER_COUNT" -ne 0 ]
			then
				echo_t "RDKB_SELFHEAL : Ping to IPv4 servers are failed."
				if [ `getCorrectiveActionState` = "true" ]
				then
					echo_t "RDKB_SELFHEAL : Taking corrective action"
					resetNeeded "" PING
				fi
			elif [ "$ping6_success" -ne 1 ] && [ "$IPV6_SERVER_COUNT" -ne 0 ]
			then
				echo_t "RDKB_SELFHEAL : Ping to IPv6 servers are failed."
				if [ `getCorrectiveActionState` = "true" ]
				then
					echo_t "RDKB_SELFHEAL : Taking corrective action"
					resetNeeded "" PING
				fi
			else
				echo_t "RDKB_SELFHEAL : One of the ping server list is empty, ping to the other list is successfull"
				echo_t "RDKB_SELFHEAL : Connectivity Test is Successfull"
			fi	

	elif [ "$ping4_success" -ne 1 ] &&  [ "$ping6_success" -ne 1 ]
	then
		echo_t "RDKB_SELFHEAL : Ping to both IPv4 and IPv6 servers are failed."
				if [ `getCorrectiveActionState` = "true" ]
				then
					echo_t "RDKB_SELFHEAL : Taking corrective action"
					resetNeeded "" PING
				fi
	elif [ "$ping4_success" -ne 1 ]
	then
		echo_t "RDKB_SELFHEAL : Ping to IPv4 servers are failed."
				if [ `getCorrectiveActionState` = "true" ]
				then
					echo_t "RDKB_SELFHEAL : Taking corrective action"
					resetNeeded "" PING
				fi
	elif [ "$ping6_success" -ne 1 ]
	then
		echo_t "RDKB_SELFHEAL : Ping to IPv6 servers are failed."
				if [ `getCorrectiveActionState` = "true" ]
				then
					echo_t "RDKB_SELFHEAL : Taking corrective action"
					resetNeeded "" PING
				fi
	else
		echo_t "RDKB_SELFHEAL : Connectivity Test is Successfull"
	fi	

	ping4_success=0
	ping4_failed=0
	ping6_success=0
	ping6_failed=0
	ping4_server_num=0
	ping6_server_num=0

}

SELFHEAL_ENABLE=`syscfg get selfheal_enable`

while [ $SELFHEAL_ENABLE = "true" ]
do

	if [ "$calcRandom" -eq 1 ] 
	then

		calcRandTimetoStartPing
		calcRandom=0
	else
		INTERVAL=`syscfg get ConnTest_PingInterval`

		if [ "$INTERVAL" = "" ] 
		then
			INTERVAL=60
		fi
		INTERVAL=$(($INTERVAL*60))
		sleep $INTERVAL
	fi


	runPingTest
	runDNSPingTest

	SELFHEAL_ENABLE=`syscfg get selfheal_enable`
	# ping -I $WAN_INTERFACE -c $PINGCOUNT 
		
done
