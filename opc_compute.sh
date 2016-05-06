#!/bin/bash

##
## Time-stamp: <2016-05-06 14:20:50 katsu> 
##

## Some program were needed for this script
## "curl"
## "jq or python"
## "base64"

#CURL="curl --trace-ascii erlog "
#CURL="curl -s -x http://your.proxy:80"
CURL="curl -s"
#JQ="jq . "
JQ="python -m json.tool "

##
## Please set parameter
##

CONF_FILE_DIR="$HOME/bin"
ADJ_TIME=9000

# Bash 4 has Associative array.If bash is ver4 on this environment,
# we use associative array.
BASH_VERSION=$(LANG=C bash --version \
    |sed -n -e 's/GNU bash, version \([0-9]\).*/\1/p')
if [ $BASH_VERSION -ge 4 ]; then
    declare -A VCABLE_GIP       # vcable and Global IP address
    declare -A GIP_HOST         # Global IP address and host
else
    declare -a HOST_INDEX       # host name(uuid) in instance
    declare -a VCABLE_INDEX     # instance and ipassociation has it.
    declare -a GLOBAL_IP_INDEX  # ipassociation and ipreservation has it.
fi
declare -a USER_ID              # account name
declare -a UNUSED_GIP_NAME      # unused IP address name on ipreservation
declare -a UNUSED_GLOBAL_IP     # unused IP address on ipreservation

##
## parameter parse ##
##

# temporary text file for auth info
SESSION_ID="temp-compute.$$"
# cut the name of CONF_FILE from command line
CONF_FILE_NAME=`echo $@ | sed -e 's/\(.*\)\(-l \)\(.*\)/\3/' | awk '{print $1}'`
CONF_FILE=$CONF_FILE_DIR/$CONF_FILE_NAME
COOKIE_FILE="compute_cookie-$CONF_FILE_NAME"

if [ -f $CONF_FILE ]; then
    . $CONF_FILE
    ANS=`echo $@ | sed -e "s/\(.*\)\(-l \)$CONF_FILE_NAME\(.*\)/\3/"`
    if [ "$ANS" != "" ]; then    
	shift 2
    fi
else
    echo "please set your \"CONF_FILE\" with -l"
    exit 1
fi  

##
## parameters
##

OPC_URL=https://"$OPC_DOMAIN"."storage.oraclecloud.com"
STORAGE_URL="$OPC_URL"/v1/Storage-"$OPC_DOMAIN"

##
## Authentication function
##

get_cookie() {
    if [ -f $COOKIE_FILE ]; then
	epoch=$(date '+%s')
	EPOCH=$( sed 's/^nimbula=//' $COOKIE_FILE | base64 --decode \
	    | LANG=C sed 's/\(.*\)expires\(.*\)expires\(.*\)/\2/' \
	    | sed -e 's/\(.*\) \([0-9]\{10,\}.[0-9]\{3,\}\)\(.*\)/\2/' \
	    | sed -e 's/\(.*\)\.\(.*\)/\1/')

#	echo "$EPOCH"
#	echo "$epoch"
## If you use gnu date, it works
#	date --date="$EPOCH"
#	date --date="$epoch"

# check $EPOCH value is valid
	RET=$(echo $EPOCH | sed -e 's/[0-9]\{10,\}/OK/')
	if [ "$RET" != OK ]; then
	    echo "Authentication has been failed"
	    echo "Please delete the file (COOKIE_FILE) $COOKIE_FILE"
	    exit 1
	fi
# compare authenticate life time on cookie file and date command
	if [ $(($EPOCH-$epoch)) -gt $ADJ_TIME ]; then

	    COMPUTE_COOKIE=$(cat $COOKIE_FILE)
	    STATUS="Authenticated with cache file $COOKIE_FILE"
	else
	    _get_cookie
	fi
    else
	_get_cookie
    fi

# uncomment next line for no caching $COOKIE_FILE
#    rm $COOKIE_FILE

}

_get_cookie() {

    RET=$($CURL -X POST \
	-H "Content-Type: application/oracle-compute-v3+json" \
	-w '%{http_code}' \
	-d "{\"user\":\"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT\",\
             \"password\":\"$OPC_PASS\"}" \
	$IAAS_URL/authenticate/ -D $SESSION_ID )
    COMPUTE_COOKIE=$( grep -i Set-cookie $SESSION_ID | cut -d';' -f 1 \
	| cut -d' ' -f 2 | tee $COOKIE_FILE )

    STATUS=$(echo $RET | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')

    if [ "$STATUS" = 204 ]; then
	STATUS="Authenticated"
    elif [ "$STATUS" = 401 ]; then
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
    rm $SESSION_ID
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
    echo "   1: global IP address"
    echo "   2: storage volume"
    echo "   3: instance"
    echo "   4: everything"
    echo
    echo -n "Choose 1,2,3,4: "
    read ans1
    case $ans1 in
	1)
	    # delete global IP address reservation
	    get_cookie
	    ipassociation_list
	    instances_list
	    ipreservation_list
	    if [ -z ${UNUSED_GLOBAL_IP[0]} ]; then
		echo
		echo "There is no unused global IP address."
		echo
		exit 1
	    fi
	    echo
	    echo "global address that is not used"
	    echo "----------------------------------"
	    echo -e "IP ADDRESS\tUNUSED OBJECT NAME"
	    for ((i = 0 ; i < ${#UNUSED_GLOBAL_IP[$i]};++i )) do
	    echo -e "${UNUSED_GLOBAL_IP[$i]}\t${UNUSED_GIP_NAME[$i]}"
	    done
	    echo "----------------------------------"
	    echo "Do you want to delete these addresses?"
	    echo -n "(1:Yes / 2:Only $OPC_ACCOUNT's / 3:No): "
	    read ans2
	    case $ans2 in
		1 | [Yy]* | "")
		    for ((i = 0 ; i < ${#UNUSED_GLOBAL_IP[@]};++i )) do
		    ipreservation_delete ${UNUSED_GIP_NAME[$i]}
		    done
		    ;;
		2 | [Oo]* )
		    for ((i = 0 ; i < ${#UNUSED_GLOBAL_IP[@]};++i )) do
		    USER1=$(echo ${UNUSED_GIP_NAME[$i]} \
			| sed -n -e 's/\([^/]*\)\/.*/\1/p')
		    if [ "$USER1" = "$OPC_ACCOUNT" ]; then
		    ipreservation_delete ${UNUSED_GIP_NAME[$i]}
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
	    if [ -z ${STORAGE_VOL[0]} ]; then
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
		1 | [Yy]* | "")
		    echo 
		    for ((i = 0 ; i < ${#STORAGE_VOL[@]}; ++i )) do
		    storage_volume_delete ${STORAGE_VOL[$i]}
		    done
		    ;;
		2 | [Oo]* )
		    for ((i = 0 ; i < ${#STORAGE_VOL[@]};++i )) do
		    USER1=$(echo ${STORAGE_VOL[$i]} \
			| sed -n -e 's/[^/]*\/\([^/]*\)\/.*/\1/p')
		    if [ "$USER1" = "$OPC_ACCOUNT" ]; then
			storage_volume_delete ${STORAGE_VOL[$i]}
		    fi
		    done
		    ;;
		*)
		    exit 1
		    ;;
	    esac
	    ;;
	3)
	    # delete Instances
	    get_cookie
	    ipassociation_list
	    instances_list list
	    if [ -z ${INSTACE_ID[0]} ]; then
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
		1 | [Yy]* | "")
		    for ((i = 0 ; i < ${#INSTANCE_ID[@]};++i )) do
		    instance_delete ${INSTANCE_ID[$i]}
		    done
		    ;;
		2 | [Oo]* )
		    for ((i = 0 ; i < ${#INSTANCE_ID[@]};++i )) do
		    USER1=$(echo ${INSTANCE_ID[$i]} \
		        | sed -n -e 's/\/[^/]*\/\([^/]*\)\/.*/\1/p')
		    if [ "$USER1" = "$OPC_ACCOUNT" ]; then
			instance_delete ${INSTANCE_ID[$i]}
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
	    echo
	    echo "Do you want to delete everything on $OPC_DOMAIN site?"
	    echo -n "(1:Yes / 2:Only $OPC_ACCOUNT's / 3:No): "
	    read ans2
	    case $ans2 in
		1 | [Yy]* | "")
		    echo "Not yet implemented"
		    ;;
		2 | [Oo]* )
		    echo "Not yet implemented"
		    ;;
		*)
		    exit 1
		    ;;
	    esac
	    ;;
    esac
}

imagelist_info() {

    IMAGELIST=/tmp/imagelist-$OPC_DOMAIN

    IMAGENAME=($($CURL -X GET -H "Cookie:$COMPUTE_COOKIE" \
	$IAAS_URL/imagelist/oracle/public/ | $JQ | tee $IMAGELIST \
        | sed -n -e 's/.*\"name\": \"\/oracle\/public\/\(.*\)\",/\1/p'))
    _IFS=$IFS
    IFS=$'\n'
    IMAGEDESC=($(sed -n -e 's/.*\"description\": \(.*\),/\1/p' $IMAGELIST ))
    echo "         SHAPE                      \"DESCRIPTION\""
    echo "-------------------------------------------------------------"
    for ((i = 0 ; i < ${#IMAGEDESC[@]};++i )) do
    printf "%-35s %s\n" ${IMAGENAME[$i]} ${IMAGEDESC[$i]}
    done
    IFS=$_IFS
    rm $IMAGELIST
}

imagelist_user_defined_info() {

    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/imagelist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

imagelistentry_info() {
    TEST_IMAGE=oel_6.4_2GB_v1
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/imagelist/oracle/public/$TEST_IMAGE/entry/1 | $JQ
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
	$CURL -X DELETE -H "Cookie: $COMPUTE_COOKIE" \
	    $IAAS_URL/instance$ans
    else
	RET=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/instance$1)
    fi
    STATUS=$(echo $RET | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$STATUS" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $RET
    fi
}

instances_list() {

    INSTANCE=/tmp/instance-$OPC_DOMAIN
    if [ "$1" == list ]; then
	echo
	echo "          OBJECT list for the Domain $OPC_DOMAIN"
	echo "============================================================="
	echo "                    ### INSTANCE ###"
	echo "============================================================="
	echo
    fi

    # sed:1 pick up object "name"
    # sed:2 omit storage attachment uuid by "uniq"
    # sed:3 choose object with uuid

    # get HOST uuid
    INSTANCE_ID=($($CURL -X GET -H "Cookie:$COMPUTE_COOKIE" \
	$IAAS_URL/instance/Compute-$OPC_DOMAIN/ | $JQ | tee $INSTANCE \
	| sed -n -e 's/.*\"name\".*\(\/Compute-.*\)\".*/\1/p' \
	| sed -e 's/\(\/Compute-.*\/.*\/.*\/.*\)\/.*/\1/' | uniq \
	| sed -n -e '/[0-9a-z]\{8\}-[0-9a-z]\{4\}-.*-.*-[0-9a-z]\{12\}/p' ))

    # get eth0 MAC address
    MAC_ADDRESS=($(grep -A1 '\"address\":' $INSTANCE \
	| sed -n -e 's/.*\"\(.*:.*:.*\)\",/\1/p'))

    # get private IP address
    PRIVATE_IP=($(sed -n -e 's/.*\"ip\": \"\(.*\)\",/\1/p' $INSTANCE ))

    # get vcable id
    VCABLE_ID=($(sed -n -e 's/.*\"vcable_id\".*\/.*\/.*\/\(.*\)\",/\1/p' \
	$INSTANCE ))

    # Now INSTANCE_ID,MAC_ADDRESS,PRIVATE_IP,VCABLE_ID has same index as row.
    # Because they are in same block in $INSTANCE file.
    # Next "for loop" use $i to pick up the factor.

    # show information
    # show account name and host name
    for ((i = 0 ; i < ${#INSTANCE_ID[@]};++i )) do
    USER1=$( echo ${INSTANCE_ID[$i]} \
	| sed -e "s/\/Compute-$OPC_DOMAIN\/\([^/]*\).*/\1/" )
    HOST_ID=$( echo ${INSTANCE_ID[$i]} \
	| sed -e "s/\/Compute-$OPC_DOMAIN\/[^/]*\(.*\)/\1/" \
	-e 's/^\///' )
    if [ "$1" == list ]; then
	echo "USER:               $USER1"
	echo "NAME:               $HOST_ID"
	# show MAC address and private IP address
	echo "MAC ADDRESS:        ${MAC_ADDRESS[$i]}"
	echo "PRIVATE IP ADDRESS: ${PRIVATE_IP[$i]}"
    fi

    # show global IP address

    if [ $BASH_VERSION = 4 ]; then
	# bash ver.4
	# VCABLE_GIP is a global parameter gotten in ipassociation_list
	# get global IP address from VCABLE_GIP
	if [ "$1" == list ]; then
	    echo "GLOBAL IP ADDRESS:  ${VCABLE_GIP[${VCABLE_ID[$i]}]}"
	    echo
	fi
	# link vcable and global IP address
	GIP=${VCABLE_GIP[${VCABLE_ID[$i]}]}
	# set global IP address and HOST name into HOST_GIP
	# to use ipreservation_list
	GIP_HOST[$GIP]=$HOST_ID
    else
	# bash ver.3
	for ((m = 0 ; m < ${#VCABLE_INDEX[@]}; ++m )) do
	if [ ${VCABLE_ID[$i]} = ${VCABLE_INDEX[$m]} ]; then
	    if [ "$1" == list ]; then
		echo "GLOBAL IP ADDRESS:  ${GLOBAL_IP_INDEX[$m]}"
		echo
	    fi
	    HOST_INDEX[$m]=$HOST_ID
	    break
	fi
	done
    fi
    done
#    rm $INSTANCE
}

ipassociation() {

    # connect vcable and ipreservation 
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/association/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

ipassociation_list() {
    # instance: "vcable_id(uuid)"
    # ipassociation: "name"(uuid),"reservation"(uuid),"vcable"(uuid)
    # ipreservation: "name"(uuid),"ip"(uuid)

    IP_ASSOC=/tmp/ipassociation-$OPC_DOMAIN

    # get user account name

    if [ -z ${USER_ID[0]} ];then
	USER_ID=($($CURL -X GET \
	    -H "Accept: application/oracle-compute-v3+directory+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    $IAAS_URL/ip/association/Compute-$OPC_DOMAIN/ | $JQ \
	    | sed -n -e 's/.*\/Compute-.*\/\(.*\)\/.*/\1/p'))
    fi
    # get the object from all users account
    # objects into $USER_ID[$i]/$OBJECT[$j]
    # $OBJECT is array of ipassociation name and ip address 

    # get all USER_ID's information from IP_ASSOC

    for ((m = 0 ; m < ${#USER_ID[@]};++m )) do
    echo checking ${USER_ID[$m]},

    # get global IP address

    GLOBAL_IP=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/association/Compute-$OPC_DOMAIN/${USER_ID[$m]}/ \
	| $JQ | tee $IP_ASSOC-${USER_ID[$m]} \
	| sed -n -e 's/.*\"ip\": \"\(.*\)\",/\1/p' ))

    # get vcable uuid

    VCABLE=($(sed -n -e 's/.*\"vcable\": \"\/.*\/.*\/\(.*\)\"/\1/p' \
	$IP_ASSOC-${USER_ID[$m]}))

    # set global IP address into VCABLE_GIP
    # "${#GLOBAL_IP[@]}" is total number of GLOBAL_IP 
    if [ $BASH_VERSION = 4 ]; then
	# bash ver.4
	# GLOBAL_IP[j] link with VCABLE[j] on associative array
	for ((n = 0 ; n < ${#GLOBAL_IP[@]}; ++n )) do
	VCABLE_GIP[${VCABLE[$n]}]=${GLOBAL_IP[$n]}
	done
    else
	# bash ver.3
	# make VCABLE_INDEX[j] and GLOBAL_IP_INDEX[j] in same index row
	for ((n = 0 ; n < ${#GLOBAL_IP[@]}; ++n )) do
	VCABLE_INDEX[${#VCABLE_INDEX[@]}]=${VCABLE[$n]}
	GLOBAL_IP_INDEX[${#GLOBAL_IP_INDEX[@]}]=${GLOBAL_IP[$n]}
	done
    fi
    rm $IP_ASSOC-${USER_ID[$m]}
    done
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
	RET=$($CURL -X POST \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    -d "{\"parentpool\":\"/oracle/public/ippool\", \
             \"account\":\"/Compute-$OPC_DOMAIN/default\",\
             \"permanent\": true, \
             \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans\"}"\
	$IAAS_URL/ip/reservation/ )
    else
	RET=$($CURL -X POST \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    -d "{\"parentpool\":\"/oracle/public/ippool\", \
             \"account\":\"/Compute-$OPC_DOMAIN/default\",\
             \"permanent\": true, \
             \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$1\"}"\
	$IAAS_URL/ip/reservation/ )
    fi
    STATUS=$(echo $RET | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    if [ "$STATUS" = 201 ]; then
	echo "$ans""$1"" created"
    else
	echo $RET
    fi
}

ipreservation_delete() {
    if [ "$1" = "" ]; then
	echo "What is the name of ipreservation to delete ?"
	read ans
	RET=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans)
    else
	RET=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/$1)
    fi
    STATUS=$(echo $RET | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$STATUS" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $RET
    fi
}

ipreservation_list() {
    # instance: "vcable_id(uuid)"
    # ipassociation: "name"(uuid),"reservation"(uuid),"vcable"(uuid)
    # ipreservation: "name"(uuid),"ip"(uuid)

    # We have to link host id to ipreservation id
    # with ipassociation_list().
    # Some time ipreservation id has no linkage with any host id.

    IP_RESERV=/tmp/ipreservation-$OPC_DOMAIN

    # get account name which use global IP address
    # using "Accept: application/oracle-compute-v3+directory+json",
    # we could get not only $OPC_ACCOUNT but another account name.
    # And ipreservation objects are only being showed on owner account's
    # sub object with "Accept: application/oracle-compute-v3+json".
    # That is why trying to get USER_ID first and to get each sub objects.

    # get user account name

    USER_ID=($($CURL -X GET \
	-H "Accept: application/oracle-compute-v3+directory+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/ | $JQ \
	| sed -n -e 's/.*\/Compute-.*\/\(.*\)\/.*/\1/p' ))

    # get the object from all users account
    # objects into $USER_ID[$i]/$OBJECT[$j]

    echo "============================================================="
    echo "         ### GLOBAL IP ADDRESS (IP RESERVATION) ###"
    echo "============================================================="
    for ((m = 0 ; m < ${#USER_ID[@]};++m )) do
    echo
    # show ACCOUNT name
    echo "USER_ID: ${USER_ID[$m]}"
    GLOBAL_IP=($($CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/${USER_ID[$m]}/ \
	| $JQ | tee $IP_RESERV-${USER_ID[$m]} \
	| sed -n -e 's/.*\"ip\": \"\(.*\)\",/\1/p' ))
    RESERVE_NAME=($(sed -n \
	-e "s/.*\"name\": \"\/Compute-$OPC_DOMAIN\/\(.*\)\",/\1/p" \
	$IP_RESERV-${USER_ID[$m]} ))

    echo "-------------------------------------------------------------"
    echo -e "IP ADDRESS\tHOST UUID"
    if [ $BASH_VERSION = 4 ]; then
	# bash ver.4
	# show Global IP Address with GIP_HOST from instance_list
	for ((i = 0 ; i < ${#GLOBAL_IP[@]}; ++i )) do
	echo -e "${GLOBAL_IP[$i]}\t${GIP_HOST[${GLOBAL_IP[$i]}]}"

	if [ "${GIP_HOST[${GLOBAL_IP[$i]}]}" = "" ]; then
	    # pickup no use IP address using in delete()
	    GIP="${GLOBAL_IP[$i]}"
	    GIP_NAME="${RESERVE_NAME[$i]}"
	    UNUSED_GLOBAL_IP[${#UNUSED_GLOBAL_IP[@]}]=$GIP
	    UNUSED_GIP_NAME[${#UNUSED_GIP_NAME[@]}]=$GIP_NAME
	fi
	done
    else
	# bash ver.3
	for ((i = 0 ; i < ${#GLOBAL_IP[@]}; ++i )) do
	for ((j = 0 ; j < ${#GLOBAL_IP_INDEX[@]}; ++j )) do
	if [ ${GLOBAL_IP[$i]} = ${GLOBAL_IP_INDEX[$j]} ]; then
	    echo -e "${GLOBAL_IP_INDEX[$j]}\t${HOST_INDEX[$j]}"
	    break
	    # it must be remaining of global IP address without HOST
	elif [ $j = $((${#GLOBAL_IP_INDEX[@]} - 1)) ]; then
	    echo -e "${GLOBAL_IP[$i]}"
	    # pickup no use IP address using in delete()
	    GIP="${GLOBAL_IP[$i]}"
	    GIP_NAME="${RESERVE_NAME[$i]}"
	    UNUSED_GLOBAL_IP[${#UNUSED_GLOBAL_IP[@]}]=$GIP
	    UNUSED_GIP_NAME[${#UNUSED_GIP_NAME[@]}]=$GIP_NAME
	fi
	done
	done
    fi
    echo "-------------------------------------------------------------"
    rm $IP_RESERV-${USER_ID[$m]}    
    done
}

launchplan() {

    echo "What is the name of new host ?"
    read HOST_NAME

    echo "What is the sshkey ? (you must upload sshkey first.)"
    read SSHKEY

    RET=$($CURL -X POST \
	-H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-w '%{http_code}' \
        -d "{\"instances\": [ \
            {\"shape\": \"oc3\",\
             \"imagelist\": \"/oracle/public/oel_6.4_2GB\",\
             \"sshkeys\": [\"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$SSHKEY\"],\
             \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$HOST_NAME\",\
             \"label\": \"$HOST_NAME\",\
             \"networking\":{\"eth0\": \
              {\"dns\": [\"$HOST_NAME\"], \
               \"seclists\": [\"/Compute-$OPC_DOMAIN/default/default\"], \
               \"nat\":\"ippool:/oracle/public/ippool\"} \
            } } ] }" \
	$IAAS_URL/launchplan/)

    STATUS=$(echo $RET | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')

    if [ "$STATUS" = 201 ]; then
	echo "$HOST_NAME created"
    else
	echo $RET
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
    #    opc_storage.sh -l $CONF_FILE_NAME _upload compute_images $FILE_NAME
    SIZE=`opc_storage.sh -l $CONF_FILE_NAME _metadata $FILE_NAME`
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

orchestration(){
    O_FILE=/tmp/orchestration-$OPC_DOMAIN
    $CURL -X GET \
        -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/orchestration/Compute-$OPC_DOMAIN/ \
	| $JQ | tee $O_FILE \
	| sed -n -e 's/.*\"name\": \"\/[^/]*\/\([^/]*\/[^/]*\/[^/\]*\).*/\1/p'\
        | uniq
}

orchestration_delete(){
#CURL="curl -v"
    O_FILE=/tmp/orchestration-$OPC_DOMAIN
    if [ "$1" = "" ]; then
	echo "Which orchestration do you want to delete ?"
	read ans
	RET=$($CURL -X DELETE \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/orchestration/$ans )
    else
	RET=$($CURL -X DELETE \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -H "Cookie: $COMPUTE_COOKIE" \
	    -w '%{http_code}' \
	    $IAAS_URL/orchestration$1 )
    fi
    STATUS=$(echo $RET | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$STATUS" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $RET
    fi

#            -H "Accept: application/oracle-compute-v3+json" \
}

role() {
    sed -e 's/nimbula=//' $COOKIE_FILE | base64 -d \
	| sed -e 's/Compute-$OPC_DOMAIN\/\(.*\)/\1/'
    echo
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
    echo "What is the name of seclist you want to delete ?"
    read ans
    $CURL -X DELETE -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/seclist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans
}

secrule() {
    $CURL -X GET -H "Accept: application/oracle-compute-v3+json" \
	 -H "Cookie: $COMPUTE_COOKIE" \
	 $IAAS_URL/secrule/Compute-$OPC_DOMAIN/ | $JQ
    echo
}

secrule_create() {
    RET=$($CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-w '%{http_code}' \
	-d "{\"dst_list\": \"seclist:/Compute-$OPC_DOMAIN/default/default\",
             \"name\": \"/Compute-$OPC_DOMAIN/PublicSSHAccess\",
             \"application\": \"/oracle/public/ssh\",
             \"src_list\" \"seciplist:/oracle/public/public-internet\",
             \"action\": \"PERMIT\" }" \
	 $IAAS_URL/secrule/ )
    STATUS=$(echo $RET | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')

    if [ "$STATUS" = 200 ]; then
	echo "secrule created"
    else
	echo $RET
    fi
}

secrule_make_default_ssh() {
    RET=$($CURL -X GET -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-w '%{http_code}' \
	$IAAS_URL/secrule/Compute-$OPC_DOMAIN/DefaultPublicSSHAccess )
    STATUS=$(echo $RET | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')

    if [ "$STATUS" = 200 ]; then
	echo "DefaultPublicSSHAccess"
	secrule_create
    else
	echo "Try to make DefaultPublicSSHAccess rule"
	secrule_create
    fi
}

shape() {
#    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" $IAAS_URL/shape/ | $JQ

    SHAPELIST=/tmp/shape-$OPC_DOMAIN

    SHAPE=($($CURL -X GET -H "Cookie:$COMPUTE_COOKIE" \
	$IAAS_URL/shape/ | $JQ | tee $SHAPELIST \
        | sed -n -e 's/.*\"name\": \"\(.*\)\",/\1/p'))
    CORE=($(sed -n -e 's/.*\"cpus\": \(.*\)\.0,/\1/p' $SHAPELIST ))
    RAM=($(sed -n -e 's/.*\"ram\": \(.*\),/\1/p' $SHAPELIST ))
    _IFS=$IFS
    IFS=$'\n'

    echo "----------------------------------------"
    echo -e "SHAPE\t  CORE\t oCPU\t RAM(GB)"
    echo "----------------------------------------"

    for ((i = 0 ; i < ${#SHAPE[@]};++i )) do
    RAM_GB=$(( ${RAM[$i]} / 1024 ))
    OCPU=$((${CORE[$i]} / 2))

    printf "%s  \t %5d\t" ${SHAPE[$i]} ${CORE[$i]}
    printf "%5d  %5d\n" $OCPU $RAM_GB

    done
    IFS=$_IFS
    rm $SHAPELIST
}    

sshkey(){
    echo "It will upload $HOME/.ssh/id_rsa.pub to the cloud" 
    echo -n "What is the name of the new sshkey ? "
    read ans
    key=$(cat $HOME/.ssh/id_rsa.pub)
    $CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-d "{ \"enabled\": true,\
              \"key\": \"$key\",\
     	      \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans\"}" \
	$IAAS_URL/sshkey/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans
    echo
}

sshkey_info(){
    $CURL -X GET -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/sshkey/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
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
CURL="curl -v"
    if [ $1 = "" ];then
	echo "Which Storage Volume do you want to delete ?"
	read ans
	RET=$($CURL -X DELETE -H "Cookie: $COMPUTE_COOKIE" \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -w '%{http_code}' \
	    -d "{ \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans\"}" \
	    $IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans )
    else
	RET=$($CURL -X DELETE -H "Cookie: $COMPUTE_COOKIE" \
	    -H "Content-Type: application/oracle-compute-v3+json" \
	    -w '%{http_code}' \
	    -d "{ \"name\": \"$1\"}" \
	    $IAAS_URL/storage/volume/$1 )
    fi
    STATUS=$(echo $RET | sed -n -e 's/.*\([0-9][0-9][0-9]$\)/\1/p')
    # If successful, "HTTP/1.1 204 No Content" is returned.
    if [ "$STATUS" = 204 ]; then
	echo "$1""$ans"" deleted"
    else
	echo $RET
    fi
}

storage_volume_info() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	-H "Accept: application/oracle-compute-v3+json" \
	$IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$1 | $JQ
}

storage_volume_list() {
    echo
    echo "============================================================="
    echo "                   ### STORAGE VOLUME ###"
    echo "============================================================="
    STORAGE_VOL=($($CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	-H "Accept: application/oracle-compute-v3+json" \
	$IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/ \
	| $JQ | sed -n -e 's/.*\"name\":[^/]*\/\(Compute-.*\)\",/\1/p' ))
    for ((i = 0 ; i < ${#STORAGE_VOL[@]}; ++i )) do
    echo ${STORAGE_VOL[$i]}
    done
}

storage_attachment() {
    $CURL -X POST -H "Cookie: $COMPUTE_COOKIE" \
	-H "Content-Type: application/oracle-compute-v3+json" \
	$IAAS_URL/storage/attachment/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/
}

case $1 in
    account)
	get_cookie
	account
	;;
    auth) 
	get_cookie
	echo $STATUS
	;;
    delete)
	delete
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
    instance)
	get_cookie
	instance
	;;
    instances)
	get_cookie
	instances
	;;
    instance-delete)
	get_cookie
	instance_delete
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
    orchestration)
	get_cookie
	orchestration
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
    shape)
	get_cookie
	shape
	;;
    show)
	get_cookie
	ipassociation_list
	instances_list list
	;;
    show-network)
	get_cookie
	instances_list
	ipreservation_list
	ipassociation_list
	;;
    sshkey)
	get_cookie
	sshkey
	;;
    sshkey-info)
	get_cookie
	sshkey_info
	;;
    storage-attachment)
	get_cookie
	storage_attachment_info
	;;
    storage-volume-info)
	get_cookie
	storage_volume_info
	;;
    storage-volume-list)
	get_cookie
	storage_volume_list
	;;
    storage-volume-create)
	get_cookie
	storage_volume_create
	;;
# Under construction
    create-minimal)
	get_cookie
	sshkey
	storage_volume_create
	seclist_add
	ipreservation
	;;
    secrule_make_default_ssh)
	get_cookie
	secrule_make_default_ssh
	;;
    *)
	cat <<-EOF
	Usage: opc_compute.sh -l "CONF_FILE" { auth | show | shape | ... } 
	 auth       -- authentication with Oracle Cloud
	 show       -- show compute instance
	 shape      -- show oCPU + Memory size template
	 imagelist  -- show OS and disk size template
	 launchplan -- make an instance for temporary
	 list       -- list all instance,ipreservation,storage volume
EOF
	exit 1
esac

exit 0
