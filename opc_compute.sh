#!/bin/bash

##
## Time-stamp: <2016-03-07 23:43:54 katsu> 
##

## Some program were needed for this script
## "curl"
## "jq"
## "base64"

#CURL="curl --trace-ascii erlog "
#CURL="curl -s -x http://your.proxy:80"
CURL="curl -s "
JQ="jq . "

##
## Please set parameter
##

CONF_FILE_DIR="$HOME/bin"
ADJ_TIME=9000

##
## paramater parse ##
##

SESSION_ID="temp-compute.$$"
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
    echo "please set your CONF_FILE with -l"
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
	epoc=$(date '+%s')
	EPOC=$( base64 -d $COOKIE_FILE \
	    | LANG=C sed -e 's/\(.*\)expires\(.*\)expires\(.*\)/\2/' \
	    | sed -e 's/\(.*\) \([0-9]\{10,\}.[0-9]\{3,\}\)\(.*\)/\2/' \
	    | sed -e 's/\(.*\)\.\(.*\)/\1/')

#	echo "@$EPOC"
#	echo "@$epoc"
#	date --date="@$EPOC"
#	date --date="@$epoc"

	if [ $(($EPOC-$epoc)) -gt $ADJ_TIME ]; then
	    COMPUTE_COOKIE=$(cat $COOKIE_FILE)
	else
	    _get_cookie
	fi
    else
	_get_cookie
    fi
#    echo $(($EPOC-$epoc))

# uncoment next line for no caching $COOKIE_FILE
#    rm $COOKIE_FILE

}

_get_cookie() {

    $CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-d "{\"user\":\"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT\",\
              \"password\":\"$OPC_PASS\"}" \
	$IAAS_URL/authenticate/ -D $SESSION_ID
    COMPUTE_COOKIE=$( grep -i Set-cookie $SESSION_ID | cut -d';' -f 1 \
	| cut -d' ' -f 2 | tee $COOKIE_FILE )

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
#	$IAAS_URL/imagelist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/create-gui3-centos/entry/1 | $JQ
}

instances() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	  $IAAS_URL/instance/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

ipassociation_info() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	  $IAAS_URL/ip/association/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

# uploaded images

machineimage() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
    	  $IAAS_URL/machineimage/Compute-$OPC_DOMAIN/ \
	  | $JQ
    echo
}    

machineimage_create(){
#    echo "What is the name of machineimage on storage cloud ?"
#    read FILE_NAME
    FILE_NAME="CentOS-7-x86_64-OracleCloud.raw.tar.gz"
    IMAGE_NAME=centos7-cui
    #    opc_storage.sh -l $CONF_FILE_NAME _upload compute_images $FILE_NAME
    SISE=`opc_storage.sh -l $CONF_FILE_NAME _metadata $FILE_NAME`
    SISE_TOTAL=`echo $SISE | tr -d '\r\n'`
    echo $SISE_TOTAL
    $CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-d "{\"account\":\"/Compute-$OPC_DOMAIN/cloud_storage\",\
              \"name\":\"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$IMAGE_NAME\",\
              \"no_upload\":true,\
              \"file\":\"compute_images/$FILE_NAME\",\
              \"sizes\":{\"upload\":$SISE_TOTAL,\
              \"total\":$SISE_TOTAL}}" \
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

seclist_create(){
    echo -n "What is the name of container do you create ? "
    read ans
    echo -n "Which is JSON file ? "
    read json
    $CURL -X POST -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	-d @"$json" \
	$IAAS_URL/seclist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans
    echo
}

seclist_name() {
    echo -n "What is the name of seclist do you retrive ? "
    read name
    $CURL -X GET -H "Content-Type: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/seclist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans \
	| $JQ
    echo
}

seclist_container() {
    echo default:
    $CURL -X GET -H "Accept: application/oracle-compute-v3+json" \
	 -H "Cookie: $COMPUTE_COOKIE" \
	 $IAAS_URL/seclist/Compute-$OPC_DOMAIN/default/ | $JQ
    echo
#    echo user:
#    $CURL -X GET -H "Accept: application/oracle-compute-v3+json" \
#	 -H "Cookie: $COMPUTE_COOKIE" \
#	 $IAAS_URL/seclist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
#    echo
}

seclist_delete(){
    echo "What is the name of seclist you want to delete ?"
    read ans
    $CURL -X DELETE -H "Accept: application/oracle-compute-v3+json" \
	-H "Cookie: $COMPUTE_COOKIE" \
	$IAAS_URL/seclist/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans
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

storage_attachment_info() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	-H "Content-Type: application/oracle-compute-v3+json" \
    $IAAS_URL/storage/attachment/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
    echo
}

storage_volume_create() {
    $CURL -X POST -H "Cookie: $COMPUTE_COOKIE" \
	-H "Content-Type: application/oracle-compute-v3+json" \
	-d "{ \"size\": \"$key\",\
     	      \"properties\": \"/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/$ans\"}" \
	$IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

storage_volume_info() {
    $CURL -X GET -H "Cookie: $COMPUTE_COOKIE" \
	-H "Content-Type: application/oracle-compute-v3+json" \
	$IAAS_URL/storage/volume/Compute-$OPC_DOMAIN/$OPC_ACCOUNT/ | $JQ
}

storage_attatchment() {
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
	echo $COMPUTE_COOKIE
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
    ipassociation-info)
	get_cookie
	ipassociation_info
	;;
    instances)
	get_cookie
	instances
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
    shape)
	get_cookie
	shape
	;;
    sshkey)
	get_cookie
	sshkey
	;;
    show)
	get_cookie
	instances
	;;
    seclist_create)
	get_cookie
	seclist_create
	;;
    seclist_container)
	get_cookie
	seclist_container
	;;
    seclist_name)
	get_cookie
	seclist_name
	;;
    seclist_delete)
	get_cookie
	seclist_delete
	;;
    storage-attachment)
	get_cookie
	storage_attachment_info
	;;
    storage-volume)
	get_cookie
	storage_volume_info
	;;
    storage-volume-create)
	get_cookie
	storage_volume_create
	;;
    *)
	echo "Usage: $0 { show | container | upload }"
	echo "  show      -- show compute"
	echo "  container -- show container"
	echo "  upload    -- make image"
	exit 1
esac

exit 0

# POST /machineimage/, POST /imagelist/, and POST /imagelistentry/ methods
