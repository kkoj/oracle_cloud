#!/bin/bash

##
## Time-stamp: <2017-06-13 22:44:11 katsu> 
##

## Some program were needed for this script
## "curl"
## "jq or python"
## "base64"

#DEBUG="on"
DEBUG="off"
#CURL="curl -s -x http://your.proxy:80"
CURL="curl -s"
#JQ="jq . "
JQ="python -m json.tool "

##
## parameters
##

ADJ_TIME=9000

DIRNAME=`dirname $0`
. $DIRNAME/opc_init.sh

# Bash 4 has Associative array.
# But Mac OS X has bash ver.3. So we do not use associative array.

declare -a HOST_UUID_ASSOC      # host name(uuid) in ipassociation
declare -a VCABLE_UUID_ASSOC    # vcable (uuid) in instance and ipassociation
declare -a GIP_USE_ASSOC        # Global IPs in ipassociation
declare -a GIP_INSTANCE         # Global IPs in instance
declare -a GIP_FREE_UUID_RE     # unused IP address name on ipreservation
declare -a GIP_FREE_RESERV      # unused IP address on ipreservation
declare -a INSTANCE_UUID        # instance name(uuid)
declare -a SECRULE              # secrule name
declare -a SECLIST              # seclist name
declare -a SSHKEY               # sshkey name
declare -a ORCHESTRATION        # orchestration name
declare -a IPNETWORK            # ipnetwork name
declare -a VIRTUALNIC           # virtualnic name
declare -a VIRTUALNICSET        # virtualnic set name
declare -a ROUTES               # Routes name
declare -a VPN                  # VPN Gateway name

SESSION_ID="$CONF_DIR/tmp-compute.$$"    # temporary text file for auth info
COOKIE_FILE="$CONF_DIR/tmp-compute_cookie-$OPC_DOMAIN"
COMPUTE_COOKIE=""

##
## Authentication function
##

get_cookie() {
    if [ -f "$COOKIE_FILE" ]; then

	epoch_date=$(date '+%s')
	epoch_cookie=$( sed 's/^nimbula=//' $COOKIE_FILE | base64 --decode \
	    | LANG=C sed 's/\(.*\)expires\(.*\)expires\(.*\)/\2/' \
	    | sed -e 's/\(.*\) \([0-9]\{10,\}.[0-9]\{3,\}\)\(.*\)/\2/' \
	    | sed -e 's/\(.*\)\.\(.*\)/\1/')

	#	echo "$epoch_cookie"
	#	echo "$epoch_date"
	## If you use gnu date, it works
	#	date --date="$epoch_cookie"
	#	date --date="$epoch_date"

	# check $epoch_cookie value is valid
	ret=$(echo $epoch_cookie | sed -e 's/[0-9]\{10,\}/OK/')

	if [ "$ret" != OK ]; then
	    echo "Authentication has been failed"
	    echo "Please delete the file (COOKIE_FILE) $COOKIE_FILE"
	    exit 1
	fi
	# compare authenticate life time on cookie file and date command
	if [ $(($epoch_cookie-$epoch_date)) -gt $ADJ_TIME ]; then

	    COMPUTE_COOKIE=$(cat $COOKIE_FILE)
	    cache_file=`basename $COOKIE_FILE`
	    status="Authenticated with cache file $cache_file"
	else
	    _get_cookie
	fi
    else
	_get_cookie
    fi

    # uncomment next line for no caching $COOKIE_FILE
    if [ $DEBUG != "on" ]; then
	rm $COOKIE_FILE
    fi
}

_get_cookie() {

    ret=$($CURL -X POST \
	-H "Content-Type: application/oracle-compute-v3+json" \
	-w '%{http_code}' \
	-d "{\"user\":\"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT\",\
             \"password\":\"$OPC_PASS\"}" \
	$IAAS_URL/authenticate/ -D $SESSION_ID )
    COMPUTE_COOKIE=$( grep -i Set-cookie $SESSION_ID | cut -d';' -f 1 \
			    | cut -d' ' -f 2 | tee $COOKIE_FILE )

    status=$(echo $ret | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')

    if [ "$status" = 204 ]; then
	status="Authenticated"
    elif [ "$status" = 401 ]; then
	echo "Incorrect username or password"
	exit 1
    else
	echo "IAAS_URL on CONFIG_FILE could not be reached."
	echo
	echo "IAAS_URL=$IAAS_URL"
	echo
	echo "Please check IAAS_URL on the web dashboard."
	echo "It is the REST Endpoint."
    fi
    if [ $DEBUG != "on" ]; then
	rm $SESSION_ID
    fi
}

##
## functions
##

account() {

    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	-H "Accept: application/oracle-compute-v3+directory+json"\
	  $IAAS_URL/account/Compute-$OPC_DOMAIN/ | $JQ
}

delete(){
    echo "Which object do you want to delete ?"
    echo
    echo "   1: instance"
    echo "   2: storage volume"
    echo "   3: global IP address"
    echo "   4: above all, seclist, secrule, sshkey, orchestration, ipnetwork"
    echo
    echo -n "Choose 1,2,3,4: "
    read ans1
    case $ans1 in
	1)
	    # delete Instances
	    get_cookie
	    ipassociation_list
	    instances_list v
	    if [ -z ${INSTANCE_UUID[0]} ]; then
		echo
		echo "There is no instance."
		echo
		exit 1
	    fi
	    echo
	    echo "----------------"
	    echo "Do you want to delete these instance?"
	    echo -n "(1:Yes / 2:Only $OPC_ACCOUNT's / 3:No): "
	    read ans2
	    case $ans2 in
		1 | [Yy]* )
		    for ((i = 0 ; i < ${#INSTANCE_UUID[@]};++i ))
		    do
			instance_delete ${INSTANCE_UUID[$i]}
		    done
		    ;;
		2 | [Oo]* )
		    for ((i = 0 ; i < ${#INSTANCE_UUID[@]};++i ))
		    do
			user1=$(echo ${INSTANCE_UUID[$i]} \
			       | sed -n -e 's/\/[^/]*\/\([^/]*\)\/.*/\1/p')
		    if [ "$user1" = "$OPC_ACCOUNT" ]; then
			instance_delete ${INSTANCE_UUID[$i]}
		    fi
		    done
		    ;;
		*)
		    exit 1
		    ;;
	    esac
	    ;;
	2)
	    # delete Storage Volume
	    get_cookie
	    storage_volume_list
	    if [ -z ${vol_name[0]} ]; then
		echo
		echo "There is no Storage Volume."
		echo
		exit 1
	    fi
	    echo
	    echo "Do you want to delete these storage volume?"
	    echo -n "(1:Yes / 2:Only $OPC_ACCOUNT's / 3:No): "
	    read ans2

	    case $ans2 in
		1 | [Yy]* )
		    echo 
		    for ((i = 0 ; i < ${#vol_name[@]}; ++i ))
		    do
			storage_volume_delete ${vol_name[$i]}
		    done
		    ;;
		2 | [Oo]* )
		    for ((i = 0 ; i < ${#vol_name[@]};++i ))
		    do
			user1=$(echo ${vol_name[$i]} \
			       | sed -n -e 's/[^/]*\/\([^/]*\)\/.*/\1/p')
			if [ "$user1" = "$OPC_ACCOUNT" ]; then
			    storage_volume_delete ${vol_name[$i]}
			fi
		    done
		    ;;
		*)
		    exit 1
		    ;;
	    esac
	    ;;
	3)
	    # delete global IP address reservation
	    get_cookie
	    ipassociation_list
	    instances_list
	    ipreservation_list
	    if [ -z ${GIP_FREE_RESERV[0]} ]; then
		echo
		echo "There is no unused global IP address."
		echo
		exit 1
	    fi
	    echo
	    echo "global address that is not used"
	    echo "----------------------------------"
	    echo -e "IP ADDRESS\tFREE OBJECT NAME"
	    for ((i = 0 ; i < ${#GIP_FREE_RESERV[$i]};++i ))
	    do
		echo -e "${GIP_FREE_RESERV[$i]}\t${GIP_FREE_UUID_RE[$i]}"
	    done
	    echo "----------------------------------"
	    echo "Do you want to delete these addresses?"
	    echo -n "(1:Yes / 2:Only $OPC_ACCOUNT's / 3:No): "
	    read ans2
	    case $ans2 in
		1 | [Yy]* )
		    for ((i = 0 ; i < ${#GIP_FREE_RESERV[@]};++i ))
		    do
			ipreservation_delete ${GIP_FREE_UUID_RE[$i]}
		    done
		    ;;
		2 | [Oo]* )
		    for ((i = 0 ; i < ${#GIP_FREE_RESERV[@]};++i ))
		    do
			user1=$(echo ${GIP_FREE_UUID_RE[$i]} \
			       | sed -n -e 's/\([^/]*\)\/.*/\1/p')
		    if [ "$user1" = "$OPC_ACCOUNT" ]; then
			ipreservation_delete ${GIP_FREE_UUID_RE[$i]}
		    fi
		    done
		    ;;
		*)
		    exit 1
		    ;;
	    esac
	    ;;
	4)
	    # delete Everything
	    get_cookie
	    ipassociation_list
	    instances_list list
	    ipreservation_list
	    storage_volume_list
	    DEFAULT_SECLIST=0 
	    seclist_list
	    DEFAULT_SECRULE=0
	    secrule_list
	    sshkey_list
	    orchestration_list
	    route_list
	    ipexchange_list
	    ipnetwork_list
	    echo
	    echo "Do you want to delete these on $OPC_DOMAIN site?"
	    echo -n "(1:Yes / 2:Only $OPC_ACCOUNT's / 3:No): "
	    read ans2
	    case $ans2 in
		1 | [Yy]* )
		    # orchestration
		    for ((i = 0 ; i < ${#ORCHESTRATION[@]}; ++i ))
		    do
			orchestration_delete ${ORCHESTRATION[$i]}
		    done
		    # route
		    for ((i = 0 ; i < ${#ROUTE[@]}; ++i ))
		    do
			route_delete ${ROUTE[$i]}
		    done
		    # ipexchange
		    for ((i = 0 ; i < ${#IPEXCHANGE[@]}; ++i ))
		    do
			ipexchange_delete ${IPEXCHANGE[$i]}
		    done
		    # ipnetwork
		    for ((i = 0 ; i < ${#IPNETWORK[@]}; ++i ))
		    do
			ipnetwork_delete ${IPNETWORK[$i]}
		    done
		    # instance
                    for ((i = 0 ; i < ${#INSTANCE_UUID[@]};++i ))
		    do
			instance_delete ${INSTANCE_UUID[$i]}
                    done
		    # storage	
		    for ((i = 0 ; i < ${#vol_name[@]}; ++i ))
		    do
			storage_volume_delete ${vol_name[$i]}
		    done
		    # global IP address
		    for ((i = 0 ; i < ${#GIP_FREE_RESERV[@]};++i ))
		    do
			ipreservation_delete ${GIP_FREE_UUID_RE[$i]}
		    done
		    # secrule
		    for ((i = 0 ; i < ${#SECRULE[@]}; ++i ))
		    do
			secrule_delete ${SECRULE[$i]}
		    done
		    if [ "$DEFAULT_SECRULE" = 0 ];then
			secrule_default_create
		    fi
		    # seclist
		    for ((i = 0 ; i < ${#SECLIST[@]}; ++i ))
		    do
			seclist_delete ${SECLIST[$i]}
                    done
		    if [ "DEFAULT_SECLIST" = 0 ];then
		    seclist_create default
		    fi
		    # sshkey
		    for ((i = 0 ; i < ${#SSHKEY[@]}; ++i ))
		    do
			sshkey_delete ${SSHKEY[$i]}
		    done
		    ;;
		2 | [Oo]* )
		    # orchestration
		    for ((i = 0 ; i < ${#ORCHESTRATION[@]}; ++i ))
		    do
			echo $i
                    user1=$(echo ${ORCHESTRATION[$i]} \
                        | sed -n -e 's/\([^/]*\)\/.*/\1/p')
			echo yyy $user1
                    if [ "$user1" = "$OPC_ACCOUNT" ]; then
		    orchestration_delete ${ORCHESTRATION[$i]}
                    fi
		    done
		    # instance
                    for ((i = 0 ; i < ${#INSTANCE_UUID[@]};++i ))
		    do
			user1=$(echo ${INSTANCE_UUID[$i]} \
			       | sed -n -e 's/\/[^/]*\/\([^/]*\)\/.*/\1/p')
			if [ "$user1" = "$OPC_ACCOUNT" ]; then
                            instance_delete ${INSTANCE_UUID[$i]}
			fi
                    done
		    # storage
	       	    for ((i = 0 ; i < ${#vol_name[@]};++i ))
		    do
			user1=$(echo ${vol_name[$i]} \
			    | sed -n -e 's/\([^/]*\)\/.*/\1/p')
			if [ "$user1" = "$OPC_ACCOUNT" ]; then
			    storage_volume_delete ${vol_name[$i]}
			fi
		    done
		    # global IP address
                    for ((i = 0 ; i < ${#GIP_FREE_RESERV[@]};++i ))
		    do
			user1=$(echo ${GIP_FREE_UUID_RE[$i]} \
				       | sed -n -e 's/\([^/]*\)\/.*/\1/p')
                    if [ "$user1" = "$OPC_ACCOUNT" ]; then
                        ipreservation_delete ${GIP_FREE_UUID_RE[$i]}
                    fi
                    done
		    # secrule
		    for ((i = 0 ; i < ${#SECRULE[@]}; ++i ))
		    do
                    user1=$(echo ${SECRULE[$i]} \
                        | sed -n -e 's/\([^/]*\)\/.*/\1/p')
                    if [ "$user1" = "$OPC_ACCOUNT" ]; then
		    secrule_delete ${SECRULE[$i]}
                    fi
		    done
		    if [ "$DEFAULT_SECRULE" = 0 ];then
		    secrule_default_create
		    fi
		    # seclist
		    for ((i = 0 ; i < ${#SECLIST[@]}; ++i ))
		    do
                    user1=$(echo ${SECLIST[$i]} \
                        | sed -n -e 's/\([^/]*\)\/.*/\1/p')
                    if [ "$user1" = "$OPC_ACCOUNT" ]; then
		    seclist_delete ${SECLIST[$i]}
                    fi
		    done
		    if [ "DEFAULT_SECLIST" = 0 ];then
		    seclist_create default
		    fi
		    # sshkey
		    for ((i = 0 ; i < ${#SSHKEY[@]}; ++i ))
		    do
                    user1=$(echo ${SSHKEY[$i]} \
                        | sed -n -e 's/\([^/]*\)\/.*/\1/p')
                    if [ "$user1" = "$OPC_ACCOUNT" ]; then
		    sshkey_delete ${SSHKEY[$i]}
                    fi
		    done
		    ;;
		*)
		    exit 1
		    ;;
	    esac
	    ;;
    esac		
}

imagelist_info() {

    imagelist=$CONF_DIR/tmp-imagelist-$OPC_DOMAIN
    imagename=($($CURL -X GET -H "Cookie:$COMPUTE_COOKIE" \
	$IAAS_URL/imagelist/oracle/public/ | $JQ | tee $imagelist \
        | sed -n -e 's/.*\"name\": \"\/oracle\/public\/\(.*\)\",/\1/p'))
    _IFS=$IFS
    IFS=$'\n'
    imagedesc=($(sed -n -e 's/.*\"description\": \(.*\),/\1/p' $imagelist ))
    echo "         SHAPE                      \"DESCRIPTION\""
    echo "-------------------------------------------------------------"
    for ((i = 0 ; i < ${#imagedesc[@]};++i ))
    do
    printf "%-35s %s\n" ${imagename[$i]} ${imagedesc[$i]}
    done
    IFS=$_IFS

    if [ $DEBUG != "on" ]; then
	rm $imagelist
    fi
}

imagelist_user_defined_info() {

    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/imagelist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

imagelistentry_info() {
    test_image=oel_6.4_2GB_v1
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/imagelist/oracle/public/$test_image/entry/1 | $JQ
}

instance() {
    echo "What instance/uuid do you want to show ?"
    read ans
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/instance/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans | $JQ
}

instances() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/instance/Compute-$OPC_DOMAIN/ | $JQ
}

instance_delete() {
    if [ "$1" = "" ]; then
	echo "What instance/uuid do you want to delete ?"
	read ans
	ret=$($CURL -X DELETE -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/instance/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans)
    else
	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/instance$1)
    fi
    status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$status" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $ret
    fi
}

instances_list() {

    instance=$CONF_DIR/tmp-instance-$OPC_DOMAIN
    if [ "$1" == list ]; then
	echo
	echo "          OBJECT list for the Domain $OPC_DOMAIN"
	echo "-------------------------------------------------------------"
	echo "                    ### INSTANCE ###"
	echo "-------------------------------------------------------------"
	if [ "$1" == list ]; then
		 echo "Host              Status  "\
		      "Private IP      Global IP"
	elif [ "$1" == v ]; then
		 echo "User             Host         MAC               "\
		      "Private IP      Global IP"
	fi
    fi

    # sed:1 pick up object "name"
    # sed:2 omit storage attachment uuid by "uniq"
    # sed:3 choose object with uuid

    # get INSTANCE uuid
    INSTANCE_UUID=($($CURL -X GET -H "Cookie:$COMPUTE_COOKIE" \
	 $IAAS_URL/instance/Compute-$OPC_DOMAIN/ | $JQ | tee $instance \
	  | sed -n -e 's/.*\"name\".*\(\/Compute-.*\)\".*/\1/p' \
	  | sed -e 's/\(\/Compute-.*\/.*\/.*\/.*\)\/.*/\1/' | uniq \
	  | sed -n -e '/[0-9a-z]\{8\}-[0-9a-z]\{4\}-.*-.*-[0-9a-z]\{12\}/p' ))
    
    # get eth0 MAC address
    mac_address=($(grep -A1 '\"address\":' $instance \
			  | sed -n -e 's/.*\"\(.*:.*:.*\)\",/\1/p'))

    # get private IP address
    private_ip=($(sed -n -e 's/.*\"ip\": \"\(.*\)\",/\1/p' $instance ))

    # get vcable id
    vcable_uuid_instance=($(sed \
	-n -e 's/.*\"vcable_id\".*\/.*\/.*\/\(.*\)\",/\1/p' $instance ))

    state=($(sed -n -e 's/.*\"state\": "\(.*\)\",/\1/p' $instance))
    shape=($(sed -n -e 's/.*\"shape\": "\(.*\)\",/\1/p' $instance))

    # Now INSTANCE_UUID,MAC_ADDRESS,private_ip,vcable_uuid_instance has
    # same index in row.
    # Because they are in same block in $INSTANCE file.
    # Next "for loop" use $i to pick up the factor.

    # view like web console
    declare -a host_name
    for ((i = 0 ; i < ${#INSTANCE_UUID[@]};++i ))
    do
	user1=$( echo ${INSTANCE_UUID[$i]} \
	    | sed -e "s/\/Compute-$OPC_DOMAIN\/\([^/]*\).*/\1/" )
	# get hostname/uuid
	host_uuid=$( echo ${INSTANCE_UUID[$i]} \
	    | sed -e "s/\/Compute-$OPC_DOMAIN\/[^/]*\(.*\)/\1/" \
	    -e 's/^\///' )
	# get hostname
	host_name[${#host_name[@]}]=$( echo $host_uuid \
	    | sed -e 's/\(.*\)[/].*/\1/' )

	for ((m = 0 ; m < ${#VCABLE_UUID_ASSOC[@]}; ++m ))
	do
	    if [[ ${vcable_uuid_instance[$i]} = ${VCABLE_UUID_ASSOC[$m]} ]];
	    then
		GIP_INSTANCE[$i]=${GIP_USE_ASSOC[$m]}
		if [ "$1" == list ]; then
		    printf "%-16s " ${host_name[$i]}
		    printf "%8s  " $state
		    printf "%-16s" ${private_ip[$i]}
		    printf "%-16s" ${GIP_USE_ASSOC[$m]}
		    printf "\n"
		elif [ "$1" == v ]; then
		    printf "%-16s " $user1
		    printf "%-12s " ${host_name[$i]}
		    printf "%17s  " ${mac_address[$i]}
		    printf "%-16s" ${private_ip[$i]}
		    printf "%-16s" ${GIP_USE_ASSOC[$m]}
		    printf "\n"
		fi
		HOST_UUID_ASSOC[$m]=$host_uuid
		break
	    fi
	done
    done

    # view for /etc/hosts file
    if [ "$1" == list ]; then
	echo "-------------------------------------------------------------"
	echo "hosts for private network"
	echo "-------------------------------------------------------------"
	for ((i = 0 ; i < ${#INSTANCE_UUID[@]};++i ))
	do
	    printf "%-16s" ${private_ip[$i]}
	    printf "%-16s " ${host_name[$i]}
	    printf "\n"
	done
	echo "-------------------------------------------------------------"
	echo "hosts for global network"
 	echo "-------------------------------------------------------------"
	for ((i = 0 ; i < ${#INSTANCE_UUID[@]};++i ))
	do
	    if [[ ${GIP_INSTANCE[$i]} != "" ]]; then
	    printf "%-16s" ${GIP_INSTANCE[$i]} 
	    printf "%-16s " ${host_name[$i]}
	    printf "\n"
	    fi
	done
    fi
    if [ $DEBUG != "on" ]; then
	rm $instance
    fi
}

ipassociation() {

    # connect vcable and ipreservation 
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/association/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

ipassociation_list() {
    # instance: "vcable_uuid_instance(uuid)"
    # ipassociation: "name"(uuid),"reservation"(uuid),"vcable"(uuid)
    # ipreservation: "name"(uuid),"ip"(uuid)

    ip_assoc=$CONF_DIR/tmp-ipassociation-$OPC_DOMAIN

    # get user account name

    user_id_assoc=($($CURL -X GET \
	-H "Accept: application/oracle-compute-v3+directory+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/association/Compute-$OPC_DOMAIN/ | $JQ \
	| sed -n -e 's/.*\/Compute-.*\/\(.*\)\/.*/\1/p'))

    # get the object from all users account
    # objects into $user_id_assoc[$i]/$OBJECT[$j]
    # $OBJECT is array of ipassociation name and ip address 

    # get all user_id_assoc's information from ip_assoc

    for ((m = 0 ; m < ${#user_id_assoc[@]};++m )) do
    echo checking ${user_id_assoc[$m]},

    # get global IP address

    global_ip_assoc=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/association/Compute-$OPC_DOMAIN/${user_id_assoc[$m]}/ \
	| $JQ | tee $ip_assoc-${user_id_assoc[$m]} \
	| sed -n -e 's/.*\"ip\": \"\(.*\)\",/\1/p' ))

    # get vcable uuid

    vcable_assoc=($(sed -n -e 's/.*\"vcable\": \"\/.*\/.*\/\(.*\)\"/\1/p' \
	$ip_assoc-${user_id_assoc[$m]}))

    # set global IP address into VCABLE_GIP
    # "${#global_ip[@]}" is total number of global_ip 

    # make VCABLE_UUID_ASSOC[j] and GIP_USE_ASSOC[j] in same index row
    for ((n = 0 ; n < ${#global_ip_assoc[@]}; ++n ))
    do
	VCABLE_UUID_ASSOC[${#VCABLE_UUID_ASSOC[@]}]=${vcable_assoc[$n]}
	GIP_USE_ASSOC[${#GIP_USE_ASSOC[@]}]=${global_ip_assoc[$n]}
    done
    if [ $DEBUG != "on" ]; then
	rm $ip_assoc-${user_id_assoc[$m]}
    fi
    done
}

ipnetwork_list() {

    I_FILE=$CONF_DIR/tmp-ipnetwork-$OPC_DOMAIN
    IPNETWORK=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/network/v1/ipnetwork/Compute-$OPC_DOMAIN/ \
	| $JQ | tee $I_FILE \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\",/\1/p'))
    
    echo
    echo IPNETWORK
    echo "-------------------------------------"
    for (( i=0 ; i < ${#IPNETWORK[@]}; i++ ))
    do
    echo "${IPNETWORK[$i]}"
    done
    echo "-------------------------------------"
    if [ $DEBUG != "on" ]; then
		rm $I_FILE
    fi
}

ipnetwork_delete() {
    if [ "$1" = "" ]; then
	echo "What is the name of ipnetwork to delete ?"
	read ans
	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/network/v1/ipnetwork/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans)
    else
	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/network/v1/ipnetwork/Compute-$OPC_DOMAIN/$1)
    fi
    status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$status" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $ret
    fi
}

ipexchange_list() {

    IE_FILE=$CONF_DIR/tmp-ipexchange-$OPC_DOMAIN
    IPEXCHANGE=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/network/v1/ipnetworkexchange/Compute-$OPC_DOMAIN/ \
	| $JQ | tee $IE_FILE \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\",/\1/p'))
    
    echo
    echo IPEXCHANGE
    echo "-------------------------------------"
    for (( i=0 ; i < ${#IPEXCHANGE[@]}; i++ ))
    do
    echo "${IPEXCHANGE[$i]}"
    done
    echo "-------------------------------------"
    if [ $DEBUG != "on" ]; then
		rm $IE_FILE
    fi
}

ipexchange_delete() {
    if [ "$1" = "" ]; then
	echo "What is the name of ipexchange to delete ?"
	read ans
	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/network/v1/ipnetworkexchange/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans)
    else
	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/network/v1/ipnetworkexchange/Compute-$OPC_DOMAIN/$1)
    fi
    status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$status" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $ret
    fi
}

ipreservation() {
    # Global IP address
    $CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

ipreservation_create() {
    if [ "$1" = "" ]; then
	echo "What is the name of ipreservation to create ?"
	read ans
	ret=$($CURL -X POST \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    -d "{\"parentpool\":\"/oracle/public/ippool\", \
             \"account\":\"/Compute-$OPC_DOMAIN/default\",\
             \"permanent\": true, \
             \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans\"}"\
	$IAAS_URL/ip/reservation/ )
    else
	ret=$($CURL -X POST \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    -d "{\"parentpool\":\"/oracle/public/ippool\", \
             \"account\":\"/Compute-$OPC_DOMAIN/default\",\
             \"permanent\": true, \
             \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$1\"}"\
	$IAAS_URL/ip/reservation/ )
    fi
    status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    if [ "$status" = 201 ]; then
	echo "$ans""$1"" created"
    else
	echo $ret
    fi
}

ipreservation_delete() {
    if [ "$1" = "" ]; then
	echo "What is the name of ipreservation to delete ?"
	read ans
	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans)
    else
	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/$1)
    fi
    status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$status" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $ret
    fi
}

ipreservation_list() {
    # There is 3 containers.
    # instance: "vcable"(uuid)
    # ipassociation: "name"(uuid),"reservation"(uuid),"vcable"(uuid)
    # ipreservation: "name"(uuid),"ip"(uuid)

    # We have to link host id to ipreservation id with ipassociation_list().
    # Some time ipreservation id has no linkage with any instance id.

    ip_reserv="$CONF_DIR"/tmp-ipreservation-"$OPC_DOMAIN"

    # get account name which use global IP address
    # using "Accept: application/oracle-compute-v3+directory+json",
    # we could get not only $OPC_ACCOUNT but another account name.
    # And ipreservation objects are only being showed on owner account's
    # sub object with "Accept: application/oracle-compute-v3+json".
    # That is why trying to get user_id_re first and to get each sub
    # objects.

    # get user account name
    user_id_re=($($CURL -X GET \
	-H "Accept: application/oracle-compute-v3+directory+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/ | $JQ \
	| sed -n -e 's/.*\/Compute-.*\/\(.*\)\/.*/\1/p' ))

    # get the object from all users account
    # objects into $user_id_re[$i]/$OBJECT[$j]
    echo "-------------------------------------------------------------"
    echo "         ### GLOBAL IP ADDRESS (IP RESERVATION) ###"
    echo "-------------------------------------------------------------"
    echo -e "User             IP ADDRESS      Host"
    # pick up every user's global IP address

    for ((m = 0 ; m < ${#user_id_re[@]};++m ))
    do
	gip_reserv=($($CURL -X GET \
            -H "Accept: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    $IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/${user_id_re[$m]}/ \
	    | $JQ | tee $ip_reserv-${user_id_re[$m]} \
	    | sed -n -e 's/.*\"ip\": \"\(.*\)\",/\1/p' ))
	resv_name=($(sed -n \
	    -e "s/.*\"name\": \"\/Compute-$OPC_DOMAIN\/\(.*\)\",/\1/p" \
	    $ip_reserv-${user_id_re[$m]} ))

	# gip_reserv is from ipreservation
	# GIP_USE_ASSOC is from ipassociation
	
	# get unused Global IP address
	
	# if there is no global IP address on ipassociation,
	# all gip_reserv on ipreservation must be unused.
	if [ "${#GIP_USE_ASSOC[@]}" == 0 ]; then
	for ((k = 0 ; k < ${#gip_reserv[@]}; ++k ))
	do
	    echo "${gip_reserv[$k]}"
	    # pickup no use IP address using in delete()
	    GIP_FREE_RESERV[${#GIP_FREE_RESERV[@]}]=${gip_reserv[$k]}
	    GIP_FREE_UUID_RE[${#GIP_FREE_UUID_RE[@]}]=${resv_name[$k]}
	done
    else
	for ((i = 0 ; i < ${#gip_reserv[@]}; ++i ))
	do
	    for ((j = 0 ; j < ${#GIP_USE_ASSOC[@]}; ++j ))
	    do
		if [ "${gip_reserv[$i]}" = "${GIP_USE_ASSOC[$j]}" ];
		then
		    # instance_list() to ipreservation_list()
		    hostname_reserv=$( echo ${HOST_UUID_ASSOC[$j]} \
				       | sed -e 's/\(.*\)[/].*/\1/' )
		    printf "%-16s " ${user_id_re[$m]}
		    printf "%-16s" ${GIP_USE_ASSOC[$j]}
		    printf "%-12s " $hostname_reserv
		    printf "\n"
		    break
		elif [ $(($j+1)) = "${#GIP_USE_ASSOC[@]}" ];then
		    # it must be without INSTANCE
		    printf "%-16s " ${user_id_re[$m]}
		    printf "%-16s" ${gip_reserv[$i]}
		    printf "\n"
		    # pickup no use IP address using in delete()
		    GIP_FREE_RESERV[${#GIP_FREE_RESERV[@]}]="${gip_reserv[$i]}"
		    GIP_FREE_UUID_RE[${#GIP_FREE_UUID_RE[@]}]="${resv_name[$i]}"
		fi
            done
	done
	if [ $DEBUG != "on" ]; then
	    rm $ip_reserv-${user_id_re[$m]}
	fi
    fi
    done
}

launchplan() {

    echo "What is the name of new host ?"
    read host_name

    echo "What is the sshkey ? (you must upload sshkey first.)"
    read SSHKEY
    ret=$($CURL -X POST \
	-H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-w '%{http_code}' \
        -d "{\"instances\": [ \
            {\"shape\": \"oc3\",\
             \"imagelist\": \"/oracle/public/OL_6.7_3GB-1.3.0-20160411\",\
             \"sshkeys\": [\"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$SSHKEY\"],\
             \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$host_name\",\
             \"label\": \"$host_name\",\
             \"attributes\": {\"userdata\": \
              {\"corente-tunnel-args\": \"--local-tunnel-address=172.16.21.3 --csg-hostname=csg.compute-gse00000626.oraclecloud.internal --csg-tunnel-address=172.16.254.1 --onprem-subnets=192.168.0.0/24\"} },\
             \"networking\":{\"eth0\": \
              {\"dns\": [\"$host_name\"], \
               \"seclists\": [\"/Compute-$OPC_DOMAIN/default/default\"], \
               \"nat\":\"ippool:/oracle/public/ippool\"} }\
             } ] }" \
	$IAAS_URL/launchplan/)

    status=$(echo $ret | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')

    if [ "$status" = 201 ]; then
	echo "$host_name created"
    else
	echo $ret
    fi
}

# uploaded images

machineimage() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
    	$IAAS_URL/machineimage/Compute-$OPC_DOMAIN/ \
	| $JQ
    echo
}    

# Under construction
# POST /machineimage/, POST /imagelist/, and POST /imagelistentry/ methods

machineimage_create(){
    #    echo "What is the name of machineimage on storage cloud ?"
    #    read FILE_NAME
    FILE_NAME="CentOS-7-x86_64-OracleCloud.raw.tar.gz"
    IMAGE_NAME=centos7-cui
    #    opc_storage.sh -l $OPC_DOMAIN _upload compute_images $FILE_NAME
    SIZE=`opc_storage.sh -l $OPC_DOMAIN _metadata $FILE_NAME`
    SIZE_TOTAL=`echo $SIZE | tr -d '\r\n'`
    echo $SIZE_TOTAL
    $CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-d "{\"account\":\"/Compute-$OPC_DOMAIN/cloud_storage\",\
              \"name\":\"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$IMAGE_NAME\",\
              \"no_upload\":true,\
              \"file\":\"compute_images/$FILE_NAME\",\
              \"sizes\":{\"upload\":$SIZE_TOTAL,\
              \"total\":$SIZE_TOTAL}}" \
	$IAAS_URL/machineimage/
    echo
}

machineimage_info(){
    $CURL -X GET -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
        $IAAS_URL/machineimage/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
    echo
}

nic() {
    $CURL -X GET -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
        $IAAS_URL/network/v1/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
    echo
}


orchestration(){
    O_FILE=/tmp/orchestration-$OPC_DOMAIN
    $CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/orchestration/Compute-$OPC_DOMAIN/ \
	| $JQ | tee $O_FILE \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\",/\1/p'
}

orchestration_container(){
    O_FILE=/tmp/orchestration-$OPC_DOMAIN
    $CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/orchestration/Compute-$OPC_DOMAIN/default
}

orchestration_delete(){
    O_FILE=/tmp/orchestration-$OPC_DOMAIN
    if [ "$1" = "" ]; then
	echo "Which orchestration do you want to delete ?"
	read ans
	ret=$($CURL -X DELETE \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/orchestration/Compute-$OPC_DOMAIN/$ans )
    else
	$CURL -X PUT \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/orchestration/Compute-$OPC_DOMAIN/$1?action=STOP

	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/orchestration/Compute-$OPC_DOMAIN/$1 )
    fi
    status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$status" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $ret
    fi
}

orchestration_list(){
    O_FILE=$CONF_DIR/orchestration-$OPC_DOMAIN
    ORCHESTRATION=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/orchestration/Compute-$OPC_DOMAIN/ \
	| $JQ | tee $O_FILE \
	| grep -B 1 "oplans\":" \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\",/\1/p'))
    
    echo
    echo ORCHESTRATION
    echo "-------------------------------------"
    for (( i=0 ; i < ${#ORCHESTRATION[@]}; i++ ))
    do
    echo "${ORCHESTRATION[$i]}"
    done
    echo "-------------------------------------"
    if [ $DEBUG != "on" ]; then
	rm $O_FILE
    fi
}

role() {
    sed -e 's/nimbula=//' $COOKIE_FILE | base64 -d \
	| sed -e 's/Compute-$OPC_DOMAIN\/\(.*\)/\1/'
    echo
}

route_list() {

    R_FILE=$CONF_DIR/tmp-route-$OPC_DOMAIN
    ROUTE=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/network/v1/route/Compute-$OPC_DOMAIN/ \
	| $JQ | tee $R_FILE \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\",/\1/p'))
    
    echo
    echo ROUTE
    echo "-------------------------------------"
    for (( i=0 ; i < ${#ROUTE[@]}; i++ ))
    do
    echo "${ROUTE[$i]}"
    done
    echo "-------------------------------------"
    if [ $DEBUG != "on" ]; then
		rm $R_FILE
    fi
}

route_delete() {
    if [ "$1" = "" ]; then
	echo "What is the name of route to delete ?"
	read ans
	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/network/v1/route/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans)
    else
	ret=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/network/v1/route/Compute-$OPC_DOMAIN/$1)
    fi
    status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$status" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $ret
    fi
}

secassociation() {
    # endpoint: secassociation/vcable_uuid/secassociation_uuid
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/secassociation/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}    

secassociation_create() {
    # endpoint: secassociation/vcable_uuid/secassociation_uuid
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/secassociation/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}    

seclist() {
    echo default:
    $CURL -X GET -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/seclist/Compute-$OPC_DOMAIN/default/ | $JQ
    echo
    echo user:
    $CURL -X GET -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/seclist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
    echo
}

seclist_create(){
    echo -n "What is the name of container do you create ? "
    read ans
    if [[ "$ans" =~ ^default$|^default/default$ ]]; then
	$CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -d "{\"name\": \"/Compute-$OPC_DOMAIN/default/default\",
                 \"outbound_cidr_policy\": \"PERMIT\",
                 \"policy\": \"DENY\" }" \
		     $IAAS_URL/seclist/Compute-$OPC_DOMAIN/$ans
    else
	echo -n "Which is JSON file ? "
	read json
	$CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
            -H "Cookie: $COMPUTE_COOKIE" \
            -d @"$json" \
            $IAAS_URL/seclist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans
    fi
    echo
}

seclist_delete(){
    if [ "$1" = "" ]; then
	echo "What is the name of seclist you want to delete ?"
	read ans
	ret=$($CURL -X DELETE -H "Accept: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/seclist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans )
    elif [ "$1" != default/default ]; then
	ret=$($CURL -X DELETE -H "Accept: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/seclist/Compute-$OPC_DOMAIN/$1 )
	# If successful, "HTTP/1.1 204 No Content" is returned.
	if [ "$status" = 204 ]; then
	    echo "$1""$ans"" deleted"
	else
	    echo $ret
	fi
    fi
}

seclist_list() {
    SECLIST=($($CURL -X GET \
	-H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/seclist/Compute-$OPC_DOMAIN/ | $JQ \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\"\,/\1/p' ))
    echo
    echo SECLIST
    echo "-------------------------------------"
    for (( i=0 ; i < ${#SECLIST[@]}; i++ ))
    do
    echo "${SECLIST[$i]}"
    if [ "${SECLIST[$i]}" = 'default/default' ]; then
	DEFAULT_SECLIST=1
    fi
    done
    echo "-------------------------------------"
}

secrule() {
    $CURL -X GET -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/secrule/Compute-$OPC_DOMAIN/ | $JQ
    echo
}

secrule_list() {
    SECRULE=($($CURL -X GET \
	-H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/secrule/Compute-$OPC_DOMAIN/ | $JQ \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\"\,/\1/p' ))
    echo
    echo SECRULE
    echo "-------------------------------------"
    for (( i=0 ; i < ${#SECRULE[@]}; i++ ))
    do
    echo "${SECRULE[$i]}"
    if [ "${SECRULE[$i]}" = 'DefaultPublicSSHAccess' ]; then
	DEFAULT_SECRULE=1
    fi
    done
    echo "-------------------------------------"
}

secrule_default_create() {
    ret=$($CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-w '%{http_code}' \
	-d "{ \"action\": \"PERMIT\",
            \"application\": \"/oracle/public/ssh\",
            \"description\": \"Default security rule for public SSH access to instances in the default security list.\",
            \"disabled\": false,
            \"dst_is_ip\": "false",
            \"dst_list\": \"seclist:/Compute-$OPC_DOMAIN/default/default\",
            \"name\": \"/Compute-$OPC_DOMAIN/DefaultPublicSSHAccess\",
            \"src_is_ip\": \"true\",
            \"src_list\": \"seciplist:/oracle/public/public-internet\" }" \
		 $IAAS_URL/secrule/ )
    status=$(echo $ret | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')
    if [ "$status" = 201 ]; then
	echo "default secrule created"
    else
	echo $ret
    fi
}

secrule_default() {
    ret=$($CURL -X GET -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-w '%{http_code}' \
	$IAAS_URL/secrule/Compute-$OPC_DOMAIN/DefaultPublicSSHAccess )
    status=$(echo $ret | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')

    if [ "$status" = 200 ]; then
	echo "DefaultPublicSSHAccess exists" 
    else
	echo "Try to make DefaultPublicSSHAccess rule"
	secrule_default_create
    fi
}

secrule_delete(){
    if [ "$1" = "" ]; then
	echo "What is the name of secrule you want to delete ?"
	read ans
	ret=$($CURL -X DELETE -H "Accept: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/secrule/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans )
    elif [ "$1" != DefaultPublicSSHAccess ]; then
	ret=$($CURL -X DELETE -H "Accept: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/secrule/Compute-$OPC_DOMAIN/$1 )
	status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
	# If successful, "HTTP/1.1 204 No Content" is returned.
	if [ "$status" = 204 ]; then
	    echo "$1""$ans"" deleted"
	else
	    echo $ret
	fi
    fi
}

shape() {
    shape_list=/tmp/shape-$OPC_DOMAIN
    shape=($($CURL -X GET -H "Cookie:$COMPUTE_COOKIE" \
	$IAAS_URL/shape/ | $JQ | tee $shape_list \
        | sed -n -e 's/.*\"name\": \"\(.*\)\",/\1/p'))
    core=($(sed -n -e 's/.*\"cpus\": \(.*\)\.0,/\1/p' $shape_list ))
    ram=($(sed -n -e 's/.*\"ram\": \(.*\),/\1/p' $shape_list ))
    _IFS=$IFS
    IFS=$'\n'

    echo "----------------------------------------"
    echo -e "SHAPE\t  CORE\t oCPU\t RAM(GB)"
    echo "----------------------------------------"

    for ((i = 0 ; i < ${#shape[@]};++i ))
    do
    ram_gb=$(( ${ram[$i]} / 1024 ))
    ocpu=$((${core[$i]} / 2))

    printf "%s  \t %5d\t" ${shape[$i]} ${core[$i]}
    printf "%5d  %5d\n" $ocpu $ram_gb

    done
    IFS=$_IFS
    if [ $DEBUG != "on" ]; then
	rm $shape_list
    fi
}    

sshkey(){
    echo "It will upload $HOME/.ssh/id_rsa.pub to the cloud" 
    echo -n "What is the name of the new sshkey ? "
    read ans
    key=$(cat $HOME/.ssh/id_rsa.pub)
    ret=$($CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-w '%{http_code}' \
	-d "{ \"enabled\": true,\
              \"key\": \"$key\",\
     	      \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans\"}" \
	$IAAS_URL/sshkey/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans)
    status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 201 Created." is returned.
    if [ "$status" = 201 ]; then
	echo "$ans"" created"
    else
	echo $ret
    fi
}

sshkey_info(){
    $CURL -X GET -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/sshkey/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

sshkey_list(){
    SSHKEY=($($CURL -X GET \
	-H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/sshkey/Compute-$OPC_DOMAIN/ | $JQ \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\"\,/\1/p' ))
    echo
    echo SSHKEY
    echo "-------------------------------------"
    for (( i=0 ; i < ${#SSHKEY[@]}; i++ ))
    do
    echo "${SSHKEY[$i]}"
    done
    echo "-------------------------------------"
}

sshkey_delete(){
    if [ "$1" = "" ]; then
	echo "What is the name of sshkey you want to delete ?"
	read ans
	ret=$($CURL -X DELETE -H "Accept: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/sshkey/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans )
    else
	ret=$($CURL -X DELETE -H "Accept: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/sshkey/Compute-$OPC_DOMAIN/$1 )
	status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
	# If successful, "HTTP/1.1 204 No Content" is returned.
	if [ "$status" = 204 ]; then
	    echo "$1""$ans"" deleted"
	else
	    echo $ret
	fi
    fi
}

storage_attachment_info() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	-H "Accept: application/oracle-compute-v3+json" \
	$IAAS_URL/storage/attachment/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/
    echo
}

storage_volume_create() {

    echo "What name of the volume do you want to create ?"
    read ans
    echo "How much size of volume do you want ?"
    read SIZE
    $CURL -X POST -H "Cookie: $COMPUTE_COOKIE" \
	-H "Content-Type: application/oracle-compute-v3+json" \
	-d "{ \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans\",\
     	      \"properties\": [\"/oracle/public/storage/default\"],\
              \"size\": \"$SIZE\"}"\
	$IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

storage_volume_delete() {

    if [ "$1" = "" ];then
	echo "Which Storage Volume do you want to delete ?"
	read ans
	ret=$($CURL -X DELETE -H "Cookie: $COMPUTE_COOKIE" \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -w '%{http_code}' \
	    -d "{ \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans\"}" \
	    $IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans )
    else
	ret=$($CURL -X DELETE -H "Cookie: $COMPUTE_COOKIE" \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -w '%{http_code}' \
	    -d "{ \"name\": \"Compute-$OPC_DOMAIN/$1\"}" \
	    $IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$1 )
    fi
    status=$(echo $ret | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$status" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $ret
    fi
}

storage_volume_info() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	-H "Accept: application/oracle-compute-v3+json" \
	$IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$1 | $JQ
}

storage_volume_list() {
    storage_vol_list=$CONF_DIR/tmp-storage_vol_list-$OPC_DOMAIN
    echo "-------------------------------------------------------------"
    echo "                   ### STORAGE VOLUME ###"
    echo "-------------------------------------------------------------"
    vol_name=($($CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	-H "Accept: application/oracle-compute-v3+json" \
	$IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/ \
 	| $JQ \
	| tee $storage_vol_list \
	| sed -n -e 's/.*\"name\":.*\/\(.*\/.*\)\",/\1/p' ))

    status=($(sed -n -e 's/.*\"status\": \"\(.*\)\",/\1/p' $storage_vol_list))
    size=($(sed -n -e 's/.*\"size\": \"\(.*\)\",/\1/p' $storage_vol_list))
    for ((i = 0 ; i < ${#vol_name[@]}; ++i ))
    do
	printf "%-16s" ${vol_name[$i]}
	printf "%8s " ${status[$i]}
	printf "%8s " "$((${size[$i]} / 1024 ** 3 ))" # show Byte to GB
	printf GB
	printf "\n"
    done
    if [ $DEBUG != "on" ]; then
	rm $storage_vol_list
    fi
}

storage_attachment() {
    $CURL -X POST -H "Cookie: $COMPUTE_COOKIE" \
	-H "Content-Type: application/oracle-compute-v3+json" \
	$IAAS_URL/storage/attachment/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/
}

vnic_list() {

    V_FILE=$CONF_DIR/tmp-vnic-$OPC_DOMAIN
    VIRTUALNIC=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/network/v1/vnic/Compute-$OPC_DOMAIN/ \
	| $JQ | tee $V_FILE \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\",/\1/p'))
    
    echo
    echo VIRTUALNIC
    echo "-------------------------------------"
    for (( i=0 ; i < ${#VIRTUALNIC[@]}; i++ ))
    do
    echo "${VIRTUALNIC[$i]}"
    done
    echo "-------------------------------------"
    if [ $DEBUG != "on" ]; then
		rm $V_FILE
    fi
}
vnicset_list() {

    VS_FILE=$CONF_DIR/tmp-vnicset-$OPC_DOMAIN
    VIRTUALNIC=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/network/v1/vnicset/Compute-$OPC_DOMAIN/ \
	| $JQ | tee $VS_FILE \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\",/\1/p'))
    
    echo
    echo VIRTUALNICSET
    echo "-------------------------------------"
    for (( i=0 ; i < ${#VIRTUALNIC[@]}; i++ ))
    do
    echo "${VIRTUALNIC[$i]}"
    done
    echo "-------------------------------------"
    if [ $DEBUG != "on" ]; then
		rm $VS_FILE
    fi
}

vpn_list() {
    VPN_FILE=$CONF_DIR/vpn-$OPC_DOMAIN
    VPN=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/Compute-$OPC_DOMAIN/ \
	| $JQ | tee $VPN_FILE \
        | sed -n -e 's/.*\"name\": \"\/[^/]*\/\(.*\)\",/\1/p'))
    
    echo
    echo VPN
    echo "-------------------------------------"
    for (( i=0 ; i < ${#VPN[@]}; i++ ))
    do
    echo "${VPN[$i]}"
    done
    echo "-------------------------------------"
    if [ $DEBUG != "on" ]; then
		rm $VPN_FILE
    fi
}

case "$ARG" in
    account)
	get_cookie
	account
	;;
    auth) 
	get_cookie
	echo $status
	;;
    config)
	config
	;;
    delete)
	delete
	;;
    delete-instance)
	get_cookie
	instance_delete
	;;
    imagelist)
	get_cookie
	imagelist_info
	;;
    imagelistentry)
	get_cookie
	imagelistentry_info
	;;
    imagelist-user-defined)
	get_cookie
	imagelist_user_defined_info
	;;
    ipassociation)
	get_cookie
	ipassociation
	;;
    ipassociation-list)
	get_cookie
	ipassociation_list
	;;
    ipreservation)
	get_cookie
	ipreservation
	;;
    ipreservation-list)
	get_cookie
	ipassociation_list
	instances_list
	ipreservation_list
	;;
    ipreservation-create)
	get_cookie
	ipreservation_create
	;;
    ipreservation-delete)
	get_cookie
	ipreservation_delete
	;;
    ipnetwork)
	get_cookie
	ipexchange_list
	ipnetwork_list
	route_list
	;;
    ipnetwork-delete)
	get_cookie
	ipnetwork_delete
	;;
    instance)
	get_cookie
	instance
	;;
    instances)
	get_cookie
	instances
	;;
    launchplan)
	get_cookie
	launchplan
	;;
    list)
	get_cookie
	ipassociation_list
	instances_list list
	ipreservation_list
	storage_volume_list
	;;
    machineimage-create)
	get_cookie
	machineimage_create
	;;
    machineimage-info)
	get_cookie
	machineimage_info
	;;
    machineimage)
	get_cookie
	machineimage
	;;
    nic)
	get_cookie
	vnic_list
	vnicset_list
	;;
    orchestration)
	get_cookie
	orchestration
	;;
    orchestration-container)
	get_cookie
	orchestration_container
	;;
    orchestration-delete)
	get_cookie
	orchestration_delete
	;;
    role)
	get_cookie
	role
	;;
    secassociation)
	get_cookie
	secassociation
	;;
    seclist)
	get_cookie
	seclist
	;;
    seclist-create)
	get_cookie
	seclist_create
	;;
    seclist_delete)
	get_cookie
	seclist_delete
	;;
    secrule)
	get_cookie
	secrule
	;;
    secrule-default)
	get_cookie
	secrule_default
	;;
    shape)
	get_cookie
	shape
	;;
    show)
	get_cookie
	ipassociation_list
	instances_list list
	;;
    sshkey)
	get_cookie
	sshkey
	;;
    sshkey-info)
	get_cookie
	sshkey_info
	;;
    sshkey-list)
	get_cookie
	sshkey_list
	;;
    storage-attachment)
	get_cookie
	storage_attachment_info
	;;
    storage-volume-info)
	get_cookie
	storage_volume_info
	;;
    storage-volume-create)
	get_cookie
	storage_volume_create
	;;
    storage-volume-delete)
	get_cookie
	storage_volume_delete
	;;
    vpn)
	get_cookie
	vpn_list
	;;
    vpn-delete)
	get_cookie
	vpn_delete
	;;
    # Under construction
    create-minimal)
	get_cookie
	sshkey
	storage_volume_create
	seclist_add
	ipreservation
	;;
    secrule-list)
	get_cookie
	secrule_list
	;;
    *)
	cat <<-EOF
	Usage: opc_compute.sh [-l "your domain" ] [ options ]

	 options:
	 auth           -- authentication with Oracle Cloud
	 show           -- show compute instance
	 sshkey         -- upload ssh-key
	 shape          -- show oCPU + Memory size template
	 imagelist      -- show OS and disk size template
	 launchplan     -- make an instance for temporary
	 list           -- list all instance,ipreservation,storage volume
	 delete         -- delete objects except JCS,DBCS auto making objects
	 config         -- make new configuration or change default setting
	 nic            -- show vNIC
EOF
	exit 1
esac

exit 0
