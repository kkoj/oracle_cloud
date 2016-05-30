##
## parameters
##

#CURL="curl -s -x http://your.proxy:80"
CURL="curl -s "

OPC_URL=""
CONF_DIR=$HOME/.oracle_cloud-1.0
IAAS_URL=""
OPC_DOMAIN=""
OPC_ACCOUNT=""
OPC_PASS=""
ARGS=""

##
## variable
##

declare -a CONTAINER         # name of container
declare -a CONTAINER_OBJECT  # name of container/object
RET=""                       # return stdout of HTTP status code
INDEX=""                     # index

##
## checking configuration
##

# directory and file

if [ -f $CONF_DIR/config-temp ]; then
    rm $CONF_DIR/config-temp
fi

if [ -f $CONF_DIR/config-main ];then
    . $CONF_DIR/config-main
else
    if [ ! -d $CONF_DIR ];then
	mkdir $CONF_DIR
    fi
fi

set_iaas_url (){
    if [ -f $CONF_DIR/config-temp ]; then
	sed -i -e '/^IAAS_URL=.*$/d' $CONF_DIR/config-temp
    fi
    echo "Please input your IaaS endpoint"
    echo "It is displayed on the right corner of compute cloud dashboard"
    echo
    echo "   like: https://api.compute.us2.oraclecloud.com"
    echo
    echo -n "https://"
    read IAAS_URL
    echo "IAAS_URL=https://$IAAS_URL" >> $CONF_DIR/config-temp
    echo
}

set_opc_domain(){
    if [ -f $CONF_DIR/config-temp ]; then
	sed -i -e '/^OPC_DOMAIN=.*$/d' $CONF_DIR/config-temp
    fi
    echo "Please input your Domain"
    echo -n "[Oracle cloud domain]: "
    read OPC_DOMAIN
    echo "OPC_DOMAIN=$OPC_DOMAIN" >> $CONF_DIR/config-temp
    echo
}

set_opc_account(){
    if [ -f $CONF_DIR/config-temp ]; then
	sed -i -e '/^OPC_ACCOUNT=.*$/d' $CONF_DIR/config-temp
    fi
    echo "Please input your account"
    echo -n "[your Oracle cloud account ID]: "
    read OPC_ACCOUNT
    echo "OPC_ACCOUNT=$OPC_ACCOUNT" >> $CONF_DIR/config-temp
    echo
}

set_opc_password(){
    if [ -f $CONF_DIR/config-temp ]; then
	sed -i -e '/^OPC_PASS=.*/d' $CONF_DIR/config-temp
    fi
    echo "Please input your password"
    echo -n "[your password]: "
    read OPC_PASS
    echo "OPC_PASS=$OPC_PASS" >> $CONF_DIR/config-temp
    echo
}

make_temp_config(){
    if [ -f $CONF_DIR/config-temp ]; then
	. $CONF_DIR/config-temp
	echo "   Now load this parameter"
	echo
	echo "   1 IaaS endpoint: $IAAS_URL"
	echo "   2 Domain:        $OPC_DOMAIN"
	echo "   3 ACCOUNT ID:    $OPC_ACCOUNT"
	echo "   4 PASSWORD:      $OPC_PASS"
	echo
	echo "OK or change parameter ?"
	echo -n "(Yes/No/1/2/3/4) "
	read ans2
	case $ans2 in
            [Yy]*)
		mv $CONF_DIR/config-temp $CONF_DIR/config-$OPC_DOMAIN
		ln -sf $CONF_DIR/config-$OPC_DOMAIN $CONF_DIR/config-main
		main_done=1
		;;
            [Nn]*)
		exit 1
		;;
	    1 )
		set_iaas_url
		;;
	    2 )
		set_opc_domain
		;;
	    3 )
		set_opc_account
		;;
	    4 )
		set_opc_password
		;;
	    *) exit 1
	       ;;
	esac
    else

    set_iaas_url	
    set_opc_domain
    set_opc_account
    set_opc_password
    make_temp_config

    fi
}

if [ -f $CONF_DIR/config-main ];then
    . $CONF_DIR/config-main
else
    main_done=0
    while [ "$main_done" == 0 ]
    do
	make_temp_config
    done
fi

##
## option parse
##

CONF_LOCATION=`echo $@ | sed -n -e 's/\(.*\)-l \(.*\)/\2/p' | awk '{print $1}'`

if [ "$CONF_LOCATION" != "" ]; then

    if [ -f $CONF_DIR/config-$CONF_LOCATION ]; then
	. $CONF_DIR/config-$CONF_LOCATION
    else
	echo
	echo "   There is no config file in $HOME/.oracle_cloud-1.0/"
	echo "   config-$CONF_LOCATION"
	echo "   Do you want to make it ?"
	echo 
	echo -n "(Yes/No): "
	read ans3
    case $ans3 in
        [Yy]* )
	    set_iaas_url
	    set_opc_domain
	    set_opc_account
	    set_opc_password
	    make_temp_config
            ;;
	[Nn]* | * )
	    exit 1
	    ;;
    esac
    . $CONF_DIR/config-main
    fi
fi

# get arguments except "-l parameter"
ARG=$( echo $@ | sed -e 's/\(.*\)\(-l *[^ ]* *\)\(.*\)/\1\3/' \
	    | awk '{print $1}' )

OPC_URL=https://"$OPC_DOMAIN"."storage.oraclecloud.com"
STORAGE_URL="$OPC_URL"/v1/Storage-"$OPC_DOMAIN"
ARCHIVE_URL="$OPC_URL"/v0/Storage-"$OPC_DOMAIN"

