#!/bin/bash
#
# Time-stamp: <2016-05-25 16:54:21 katsu>
#
# Some program were needed for this script
#
# "curl"

##
## set parameters
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
ARCHIVE_URL="$OPC_URL"/v0/Storage-"$OPC_DOMAIN"
AUTH_HEADER="temp-storage.$$"
RESTORE_FILE="temp-restore.$$"

##
## variable
##

declare -a CONTAINER         # name of container
declare -a CONTAINER_OBJECT  # name of container/object
RET=""                       # return stdout of HTTP status code
INDEX=""                     # index

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

archive_container_create() {
    echo -n "What is the name of new container ?  "
    read ans
    $CURL -X PUT -H "$AUTH_TOKEN" \
	-H "X-Storage-Class: Archive" \
	$STORAGE_URL/$ans
    echo
}

archive_container_delete() {
    container_delete
}

archive_download() {
    download
}

archive_upload(){
    upload
}

archive_restore() {
    echo "What containerName/objectName do you want to restore ?"
    read ans
    RET=$($CURL -X POST -H "$AUTH_TOKEN" \
	"$ARCHIVE_URL/$ans?restore" -w '%{http_code}')

    # get the status code
    STATUS=$(echo $RET | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')

    if [ $STATUS = 200 ]; then
	echo "Object has been restored or is being retrieved"
    elif [ $STATUS = 202 ]; then
	echo "Object is being retrieved"
    elif [ $STATUS = 404 ]; then
	echo "The specified resource doesn't exist"
    else
	# It is not a status code.
	echo $RET
    fi
}

container_create() {
    echo -n "What is the name of new container ?  "
    read ans
    $CURL -X PUT -H "$AUTH_TOKEN" $STORAGE_URL/$ans
    echo
}

# "compute_images" is a reserved word for boot images container.

container_compute_images() {
    echo /compute_images
    $CURL -X GET -H "$AUTH_TOKEN" "$STORAGE_URL/compute_images"
}    

containers_info() {
    $CURL -X GET -H "$AUTH_TOKEN" "$STORAGE_URL"
}    

containers_list() {

# object is $CONTAINER[$i]/$OBJECT[$j]
    echo "Listing.."
    CONTAINER=($($CURL -X GET -H "$AUTH_TOKEN" "$STORAGE_URL" ))
    for ((i = 0 ; i < ${#CONTAINER[@]};++i )) do
    OBJECT=($($CURL -X GET -H "$AUTH_TOKEN" $STORAGE_URL/${CONTAINER[$i]}))
    echo /${CONTAINER[$i]}
    for ((j = 0 ; j < ${#OBJECT[@]};++j )) do
    echo /${CONTAINER[$i]}/${OBJECT[$j]}
    CONTAINER_OBJECT[${#CONTAINER_OBJECT[@]}]=${CONTAINER[$i]}/${OBJECT[$j]}
    done
    done
    echo

}

delete() {

    if [ -z "${CONTAINER[0]}" ]; then
        echo
        echo "There is no container or object to delete"
        echo
        exit 1
    fi

    echo "Which object do you want to delete ?"
    echo
    echo "   1: one of storage objects"
    echo "   2: ALL storage objects"
    echo
    echo -n "(1:chose one / 2: DELETE All): "
    read ans1

    case $ans1 in
	1)
	    echo "Which container or container/object do you want to delete ?"
	    read ans2
	    RET=$($CURL -X DELETE \
		-w '%{http_code}' \
		-H "$AUTH_TOKEN" $STORAGE_URL/$ans2)
	    delete_status input
	    ;;
	2)

	    if [ -z "${CONTAINER[0]}" ]; then
		echo
		echo "There is no container or object to delete"
		echo
		exit 1
	    fi

	    # some file could not delete but replace the file with null file
	    # then it could be deleted.

	    TMP_DIR=/tmp/storage-object-delete-$$
	    mkdir $TMP_DIR

	    for ((INDEX = 0 ; INDEX < ${#CONTAINER_OBJECT[@]};++INDEX )) do

	    # prepare null file

	    FILE_NAME=`basename ${CONTAINER_OBJECT[$INDEX]}`

	    cd $TMP_DIR
	    touch $FILE_NAME

	    # replace null file

	    RET=$($CURL -X PUT \
		-w '%{http_code}' \
		-H "$AUTH_TOKEN" \
		-T $FILE_NAME \
		$STORAGE_URL/${CONTAINER_OBJECT[$INDEX]})

	    RET=$($CURL -X DELETE \
		-w '%{http_code}' \
		-H "$AUTH_TOKEN" \
		$STORAGE_URL/${CONTAINER_OBJECT[$INDEX]})
	    delete_status object
	    done
	    for ((INDEX = 0 ; INDEX < ${#CONTAINER[@]};++INDEX )) do
	    RET=$($CURL -X DELETE \
		-w '%{http_code}' \
		-H "$AUTH_TOKEN" \
		$STORAGE_URL/${CONTAINER[$INDEX]})
	    delete_status container
	    done
	    rm -rf $TMP_DIR
	    echo

	    ;;
	*)
	    exit 1
	    ;;
    esac
}

delete_status() {

    # get the status code
    STATUS=$(echo $RET | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')
    if [ "$STATUS" = 204 ]; then
	if [ $1 = input ]; then
	    echo " $ans2 was deleted"
	elif [ $1 = object ]; then
	    echo " ${CONTAINER_OBJECT[$INDEX]} was deleted"
	elif [ $1 = container ]; then
	    echo " ${CONTAINER[$INDEX]} was deleted"
	fi
    elif [ "$STATUS" = 409 ]; then
	echo "${CONTAINER[$INDEX]} exists, but isn't empty"
    else
	# It is not a status code.
	echo $RET
    fi
}

download() {
    echo "What containerName/objectName do you want to download ?"
    read ans
    FILE_NAME=`basename $ans`
    RET=$($CURL -X GET -H "$AUTH_TOKEN" \
	 -w '%{http_code}' -o $FILE_NAME $STORAGE_URL/$ans )

    # get the status code
    STATUS=$(echo $RET | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')
    if [ "$STATUS" = 200 ]; then
	echo "Object has been restored or is being retrieved"
    elif [ "$STATUS" = 404 ]; then
	echo "The specified resource doesn't exist"
	rm $FILE_NAME
    else
	# It is not a status code.
	echo $RET
	rm $FILE_NAME
    fi
}

upload(){
    echo "Which container do you want to use ? "
    read ans
    echo "Which file do you want to upload ? "
    read ans2
    FILE_NAME=`basename $ans2`
    RET=$($CURL -X PUT -H "$AUTH_TOKEN" \
	-H "X-Storage-Class: Archive" \
	-w '%{http_code}' \
	-T $ans2 $STORAGE_URL/$ans/$FILE_NAME )
    # get the status code
    STATUS=$(echo $RET | sed -e 's/.*\([0-9][0-9][0-9]$\)/\1/')

    if [ "$STATUS" = 201 ]; then
	echo "Object $FILE_NAME was created"
    else
	echo $RET
    fi
}

_upload_file(){
    FILE_NAME=`basename $2`
    $CURL -X PUT -H "$AUTH_TOKEN" -T $2 $STORAGE_URL/$1/$FILE_NAME
    echo $STORAGE_URL/$1/$FILE_NAME
    echo
}

metadata_info(){
    echo -n "Which container do you want to know ? "
    read ans
    echo -n "Which file do you want to know ? "
    read ans2
    FILE_NAME=`basename $ans2`
    $CURL -I -X HEAD -H "$AUTH_TOKEN" $STORAGE_URL/$ans/$FILE_NAME
    echo
}

# "compute_images" is a reserved word for boot images.

_metadata_info(){
    $CURL -I -X HEAD -H "$AUTH_TOKEN" $STORAGE_URL/compute_images/$1 | \
	grep Content-Length: | awk '{print $2}'
}

case "$1" in
    auth)
	get_auth
	echo $AUTH_TOKEN
	echo $STORAGE_URL
	;;
    archive-download)
	get_auth
	archive_download
	;;
    archive-upload)
	get_auth
	archive_upload
	;;
    create)
	get_auth
	container_create
	;;
    create-archive)
	get_auth
	archive_container_create
	;;
    delete)
	get_auth
	containers_list
	delete
	;;
    delete2)
	get_auth
	containers_list
	delete2
	;;
    download)
	get_auth
	download
	;;
    images)
	get_auth
	container_compute_images
	;;
    list)
	get_auth
	containers_list
	;;
    metadata)
	get_auth
	metadata_info $2 $3
	;;
    _metadata)
	get_auth
	_metadata_info $2
	;;
    restore)
	get_auth
	archive_restore
	;;
    show)
	get_auth
	containers_info
	;;
    upload)
	get_auth
	upload
	;;
    _upload)
	get_auth
	_upload $2 $3
	;;
    *)
	cat <<-EOF
	Usage: opc_storage.sh -l "CONF_FILE" { list | create | upload | ... }
	  list           -- list container/object
	  create         -- make new container for standard storage
	  create-archive -- make new container for archive storage
	  restore        -- restore archived file
	  upload         -- upload local file
	  delete         -- delete container or container/object

	When you want to down load archived files, restore it first.
EOF
	exit 1
esac

exit 0
