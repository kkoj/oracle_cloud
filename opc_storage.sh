#!/bin/bash
#
# Time-stamp: <2016-03-15 12:41:27 katsu> 
#
## Some program were needed for this script
## "curl"

##
## set paramaters
##

CONF_FILE_DIR="$HOME/bin"
#CURL="curl -s -x http://your.proxy:80"
CURL="curl -s "

##
## option parse
##

CONF_FILE_NAME=`echo $@ | sed -e 's/\(.*\)\(-l \)\(.*\)/\3/' | awk '{print $1}'`
CONF_FILE=$CONF_FILE_DIR/$CONF_FILE_NAME

if [ -f $CONF_FILE ]; then
    . $CONF_FILE
    ANS=`echo $@ | sed -e "s/\(.*\)\(-l \)$CONF_FILE_NAME\(.*\)/\3/"`
    if [ "$ANS" != "" ]; then
	shift 2
    fi
else
    echo
    echo "Please check CONF_FILE"
    echo
fi

##
## setting parameters
##

OPC_URL=https://"$OPC_DOMAIN"."storage.oraclecloud.com"
STORAGE_URL="$OPC_URL"/v1/Storage-"$OPC_DOMAIN"
AUTH_HEADER="temp-storage.$$"

##
## functions
##

get_auth() {
    $CURL -X GET \
    -H "X-Storage-User: Storage-$OPC_DOMAIN:$OPC_ACCOUNT" \
    -H "X-Storage-Pass: $OPC_PASS" "$OPC_URL/auth/v1.0" \
    -D $AUTH_HEADER
    X_AUTH_TOKEN=`grep -i X-Auth-Token: $AUTH_HEADER`
    X_STORAGE_URL=`grep -i X-Storage-Url: $AUTH_HEADER | awk '{print $2}'`
    AUTH_TOKEN=`echo $X_AUTH_TOKEN | tr -d '\r\n'`
    STORAGE_URL=`echo $X_STORAGE_URL | tr -d '\r\n'`
    rm $AUTH_HEADER
}

containers_info() {
    $CURL -X GET -H "$AUTH_TOKEN" "$STORAGE_URL"
    echo
}    

container_info() {
    echo -n "Which container do you want to know ? "
    read ans
    $CURL -X GET -H "$AUTH_TOKEN" $STORAGE_URL/$ans
}

container_create() {
    echo -n "What is the name of new container ?  "
    read ans
    $CURL -X PUT -H "$AUTH_TOKEN" $STORAGE_URL/$ans
    echo
}

upload_file(){
    echo -n "Which container do you want to use ? "
    read ans
    echo -n "Which file do you want to upload ? "
    read ans2
    FILE_NAME=`basename $ans2`
    $CURL -X PUT -H "$AUTH_TOKEN" -T $ans2 $STORAGE_URL/$ans/$FILE_NAME
    echo
}

_upload_file(){
    FILE_NAME=`basename $2`
    $CURL -X PUT -H "$AUTH_TOKEN" -T $2 $STORAGE_URL/$1/$FILE_NAME
    echo $STORAGE_URL/$1/$FILE_NAME
    echo
}

metadata_info(){
    echo "Which file do you want to know ?"
    read ans
    #    $CURL -I -X HEAD -H "$AUTH_TOKEN" $STORAGE_URL/compute_images/$ans | \
    $CURL -I -X HEAD -H "$AUTH_TOKEN" $STORAGE_URL/compute_images/
#	grep Content-Length: | awk '{print $2}'
    echo
}

_metadata_info(){
    $CURL -I -X HEAD -H "$AUTH_TOKEN" $STORAGE_URL/compute_images/$1 | \
	grep Content-Length: | awk '{print $2}'
}
    
delete_container() {
    echo -n "Which container do you delete ?  "
    read ans
    $CURL -X DELETE -H "$AUTH_TOKEN" $STORAGE_URL/$ans
    echo
}

case "$1" in
    auth)
	get_auth
	echo $AUTH_TOKEN
	echo $STORAGE_URL
	;;
    show)
	get_auth
	containers_info
	;;
    container)
	get_auth
	container_info
	;;
    create)
	get_auth
	container_create
	;;
    upload)
	get_auth
	upload_file
	;;
    _upload)
	get_auth
	_upload_file $2 $3
	;;
    metadata)
	get_auth
	metadata_info
	;;
    _metadata)
	get_auth
	_metadata_info $2
	;;
    delete)
	get_auth
	show_containers
	delete_container
	;;
    *)
	echo "Usage: $0 { show | create | upload | delete }"
	echo "  show     -- show containers"
	echo "  create   -- make new container"
	echo "  upload   -- upload image"
	echo "  delete   -- delete container"
	exit 1
esac

exit 0
