#!/bin/bash

##
## Time-stamp: <2016-04-13 16:59:23 katsu> 
##

## Some program were needed for this script
## "curl"
## "jq or python"
## "base64"

#CURL="curl --trace-ascii erlog "
#CURL="curl -s -x http://your.proxy:80"
CURL="curl -s "
#JQ="jq . "
JQ="python -m json.tool "

##
## Please set parameter
##

CONF_FILE_DIR="$HOME/bin"
ADJ_TIME=9000

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
fi  

##
## parameters
#

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

    if [ $STATUS = 204 ]; then
	STATUS="Authenticated"
    elif [ $STATUS = 401 ]; then
	echo "Incorrect username or password"
    else
	echo "IAAS_URL on CONFIG_FILE could not be reached."
	echo
	echo "IAAS_URL=$IAAS_URL"
	echo
	echo "Please check IAAS_URL on the web dashboard."
	echo "It is the REST endpoint."
    fi
    rm $SESSION_ID
}

##
## functions
##

account() {

    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	  -H "Content-Type: application/oracle-compute-v3+json" \
	  $IAAS_URL/account/Compute-$OPC_DOMAIN/ | $JQ
    echo
}

imagelist_info() {

    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/imagelist/oracle/public/ | $JQ
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
    echo "What instance/uuid do you want to delete ?"
    read ans
    $CURL -X DELETE -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/instance/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans
}

ipassociation() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/association/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

ipreservation() {
    $CURL -X GET -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

ipreservation_create() {
    HOST_NAME=$1
    $CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-d "{\"parentpool\":\"/oracle/public/ippool\", \
             \"account\":\"/Compute-$OPC_DOMAIN/default\",\
             \"permanent\": true, \
             \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$HOST_NAME\"}"\
	$IAAS_URL/ip/reservation/
}

ipreservation_delete() {
    echo "What is the name of ipreservation to delete ?"
    read ans
    $CURL -X DELETE -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/ip/reservation/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans
}

launchplan() {

    echo "What is the name of new host ?"
    read HOST_NAME

    echo "What is the sshkey ? (you must upload sshkey first.)"
    read SSHKEY

#    ipreservation_create $HOST_NAME

#    CURL="curl -v "
    RET=$($CURL -X POST \
	-H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-w '%{http_code}' \
        -d "{\"instances\": [ \
            {\"shape\": \"oc3\",\
             \"imagelist\": \"/oracle/public/oel_6.4_2GB_v1\",\
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

    if [ $STATUS = 201 ]; then
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

role() {
    sed -e 's/nimbula=//' $COOKIE_FILE | base64 -d \
	| sed -e 's/Compute-$OPC_DOMAIN\/\(.*\)/\1/'
    echo
}

shape() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" $IAAS_URL/shape/ | $JQ
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
    echo -n "Which is JSON file ? "
    read json
    $CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-d "$json" \
	$IAAS_URL/seclist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans
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

    if [ $STATUS = 200 ]; then
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

    if [ $STATUS = 200 ]; then
	echo "DefaultPublicSSHAccess"
	secrule_create
    else
	echo "Try to make DefaultPublicSSHAccess rule"
	secrule_create
    fi
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
	-H "Content-Type: application/oracle-compute-v3+json" \
    $IAAS_URL/storage/attachment/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
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
    $CURL -X POST -H "Cookie: $COMPUTE_COOKIE" \
	-H "Content-Type: application/oracle-compute-v3+json" \
	-d "{ \"name\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans\"}" \
	$IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

storage_volume_info() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	-H "Content-Type: application/oracle-compute-v3+json" \
	$IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$1 | $JQ
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
    ipreservation)
	get_cookie
	ipreservation
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
	instances
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
	Usage: opc_compute.sh -l "CONF_FILE" { show | shape | imagelist | launchplan } 
	 auth       -- authentication with Oracle Cloud
	 show       -- show compute instance
	 shape      -- show OCPU + Memory size template
	 imagelist  -- show OS and disk size template
	 launchplan -- make an instance for temporary
EOF

	exit 1
esac

exit 0
