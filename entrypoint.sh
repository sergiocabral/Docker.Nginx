#!/bin/bash

set -e;

printf "                                                     .                  \n";
printf "   ___      _                                       ":"                 \n";
printf "  / __\__ _| |__  _ __ ___  _ __   ___  ___       ___:____     |"\/"|   \n";
printf " / /  / _' | '_ \| '__/ _ \| '_ \ / _ \/ __|    ,'        '.    \  /    \n";
printf "/ /__| (_| | |_) | | | (_) | | | |  __/\__ \    |  O        \___/  |    \n";
printf "\____/\__,_|_.__/|_|  \___/|_| |_|\___||___/  ~^~^~^~^~^~^~^~^~^~^~^~^~ \n";
printf "          __      _                                                     \n";
printf "       /\ \ \__ _(_)_ __  __  __                                        \n";
printf "      /  \/ / _' | | '_ \ \ \/ /          https://github.com            \n";
printf "     / /\  / (_| | | | | | >  <                 /sergiocabral           \n";
printf "     \_\ \/ \__, |_|_| |_//_/\_\               /Docker.Nginx            \n";
printf "            |___/                                                       \n";
printf "\n";

printf "Entrypoint for docker image: nginx\n";

# Variables to configure externally.
NGINX_ARGS="$* $NGINX_ARGS";

NGINX_USER="nginx";
NGINX_EXECUTABLE=$(which nginx || echo "");
CERTBOT_EXECUTABLE=$(which certbot || echo "");
SUFFIX_TEMPLATE=".template";
PREFIX_SITE="site-";
DEFAULT_SERVER_NAME="default_server";
DIR_CONF="/etc/nginx";
DIR_CONF_BACKUP="$DIR_CONF.original";
DIR_CONF_DOCKER="$DIR_CONF.conf";
DIR_CONF_D="$DIR_CONF/conf.d";
DIR_CONF_D_TEMPLATES="$DIR_CONF.templates";
DIR_CERTIFICATES="$DIR_CONF.certificates";
DIR_CERTIFICATES_DEFAULT="$DIR_CERTIFICATES/$DEFAULT_SERVER_NAME";
FILE_CERTIFICATE_DEFAULT="$DIR_CERTIFICATES_DEFAULT/autosigned";
DIR_SCRIPTS="${DIR_SCRIPTS:-/root}";
DIR_SITES="/home";
DIR_SITES_ROOT="www";
DIR_DEFAULT_SERVER="$DIR_SITES/$DEFAULT_SERVER_NAME";
DIR_CERTBOT_CERTIFICATES="/etc/letsencrypt/live";
DIR_CERTBOT_WEBROOT="/tmp/letsencrypt";
LS="ls --color=auto -CFl";

if [ ! -e "$NGINX_EXECUTABLE" ];
then
    printf "Nginx is not installed.\n" >> /dev/stderr;
    exit 1;
fi

if [ ! -e "$CERTBOT_EXECUTABLE" ];
then
    printf "Certbot is not installed.\n" >> /dev/stderr;
    exit 1;
fi

IS_FIRST_CONFIGURATION=$((test ! -d $DIR_CONF_BACKUP && echo true) || echo false);

if [ $IS_FIRST_CONFIGURATION = true ];
then
    printf "This is the FIRST RUN.\n";
    
    printf "Running nginx for the first time.\n";

    USER=nginx;

    DIR="/var/log/nginx";   mkdir -p $DIR && chown -R $USER:$USER $DIR;
    DIR="/run/nginx";       mkdir -p $DIR && chown -R $USER:$USER $DIR;

    $NGINX_EXECUTABLE;
    sleep 1;

    printf "Configuring directories.\n";

    mkdir -p $DIR_CERTIFICATES;

    mkdir -p $DIR_CONF_BACKUP && cp -R $DIR_CONF/* $DIR_CONF_BACKUP;
    mkdir -p $DIR_CONF_DOCKER && cp -R $DIR_CONF/* $DIR_CONF_DOCKER;
    rm -R $DIR_CONF;
    ln -s $DIR_CONF_DOCKER $DIR_CONF;

    mkdir -p $DIR_CONF_D_TEMPLATES;

    if [ -d "$DIR_CONF_D_TEMPLATES" ] && [ ! -z "$(ls -A $DIR_CONF_D_TEMPLATES)" ];
    then
        printf "Warning: The $DIR_CONF_D_TEMPLATES directory already existed and will not have its content overwritten.\n";
    else
        printf "Creating files templates in $DIR_CONF_D_TEMPLATES\n";

        cp -R $DIR_CONF_D/* $DIR_CONF_D_TEMPLATES;
        ls -1 $DIR_CONF_D_TEMPLATES | \
           grep -v $SUFFIX_TEMPLATE | \
           grep -v $PREFIX_SITE | \
           xargs -I {} mv $DIR_CONF_D_TEMPLATES/{} $DIR_CONF_D_TEMPLATES/{}$SUFFIX_TEMPLATE;

        FILE_CONF="$DIR_CONF_D_TEMPLATES/default.conf$SUFFIX_TEMPLATE";
        printf "Adjusting default configuration file template: $(basename $FILE_CONF)\n";

        SITE_DIR_NAME=$DEFAULT_SERVER_NAME;
        echo "" >> $FILE_CONF;
        echo "server {" >> $FILE_CONF;
        echo "    listen              443 ssl;" >> $FILE_CONF;
        echo "    listen              [::]:443 ssl;" >> $FILE_CONF;
        echo "    ssl_certificate     $FILE_CERTIFICATE_DEFAULT.crt;" >> $FILE_CONF;
        echo "    ssl_certificate_key $FILE_CERTIFICATE_DEFAULT.key;" >> $FILE_CONF;
        echo "    access_log          /var/log/nginx/${SITE_DIR_NAME}-443-access.log;" >> $FILE_CONF;
        echo "    error_log           /var/log/nginx/${SITE_DIR_NAME}-443-error.log;" >> $FILE_CONF;
        echo "    return              301 http://\$host\$request_uri;" >> $FILE_CONF;
        echo "}" >> $FILE_CONF;

    fi
    $LS -Ad $DIR_CONF_D_TEMPLATES/*;

    printf "Configured directories:\n";

    chown -R $USER:$USER $DIR_CONF_BACKUP;
    chown -R $USER:$USER $DIR_CONF_DOCKER;
    chown -R $USER:$USER $DIR_CONF_D_TEMPLATES;
    
    $LS -d $DIR_CONF $DIR_CONF_BACKUP $DIR_CONF_DOCKER $DIR_CONF_D_TEMPLATES;

    printf "Created common template files.\n";
    echo "# This file will be inserted for any site into section: server { <inserted here> }" > $DIR_CONF_D/server-common.conf.part;
    cp -f $DIR_CONF_D/server-common.conf.part $DIR_CONF_D_TEMPLATES/server-common.conf.part$SUFFIX_TEMPLATE;
    echo "# This file will be inserted for any site into section: server { location /directory { <inserted here> } }" > $DIR_CONF_D/location-common.conf.part;
    cp -f $DIR_CONF_D/location-common.conf.part $DIR_CONF_D_TEMPLATES/location-common.conf.part$SUFFIX_TEMPLATE;
else
    printf "This is NOT the first run.\n";

    $NGINX_EXECUTABLE;
    sleep 1;
fi

DIR_CERTIFICATES_HOST="$DIR_CERTIFICATES_DEFAULT";
DIR_CERTIFICATES_HOST_FULLCHAIN="$FILE_CERTIFICATE_DEFAULT.crt";
DIR_CERTIFICATES_HOST_PRIVKEY="$FILE_CERTIFICATE_DEFAULT.key";

if [ ! -s "$DIR_CERTIFICATES_HOST_FULLCHAIN" ] || [ ! -s "$DIR_CERTIFICATES_HOST_PRIVKEY" ];
then

    printf "Creating auto-signed certificate to default site.\n";

    mkdir -p $DIR_CERTIFICATES_HOST;
    rm -Rf $DIR_CERTIFICATES_HOST_FULLCHAIN;
    rm -Rf $DIR_CERTIFICATES_HOST_PRIVKEY;

    openssl \
        req \
        -x509 \
        -nodes \
        -days 365 \
        -newkey rsa:2048 \
        -keyout "$DIR_CERTIFICATES_HOST_PRIVKEY" \
        -out "$DIR_CERTIFICATES_HOST_FULLCHAIN" \
        -subj "/C=/ST=/L=/O=/CN=";

    date -u >> $DIR_CERTIFICATES_HOST/DATETIME;

    printf "Auto-signed certificate files created:\n";
else
    printf "Auto-signed certificate files already exist:\n";
fi
$LS -d $DIR_CERTIFICATES_HOST/*;

printf "Removing previous site configurations.\n";
rm -f $DIR_CONF_D/$PREFIX_SITE*;

INDEX_HOST=1;
while [ -n "$(VAR_NAME="HOST${INDEX_HOST}_URL"; echo "${!VAR_NAME}")" ];
do
    VAR_NAME="HOST${INDEX_HOST}_URL";
    URLS_ALL=${!VAR_NAME};
    readarray -t URLS < <($DIR_SCRIPTS/split-to-lines.sh " " "$URLS_ALL");

    printf "Configuring HOST$INDEX_HOST (${URLS[0]}).\n";

    VAR_NAME="HOST${INDEX_HOST}_LOCATION";
    SERVER=${!VAR_NAME};
    
    VAR_NAME="HOST${INDEX_HOST}_SSL_EMAIL";
    SSL_EMAIL=${!VAR_NAME};

    VAR_NAME="HOST${INDEX_HOST}_AUTH";
    AUTH_INFO=${!VAR_NAME};

    VAR_NAME="HOST${INDEX_HOST}_NGINX_CONFIG";
    NGINX_CONFIG=${!VAR_NAME};

    SSL_ENABLE=$( (test -n "$SSL_EMAIL" && echo true) || echo false )
    AUTH_ENABLE=$( (test -n "$AUTH_INFO" && echo true) || echo false );

    AUTH_USERS=();
    AUTH_PASSWORDS=();

    readarray -t SERVER_PARTS < <($DIR_SCRIPTS/split-to-lines.sh ":" "$SERVER:");
    SITES="";
    SERVER_NAME=${SERVER_PARTS[0]};
    SERVER_PORT=${SERVER_PARTS[1]};    

    if [ ! -z "$SERVER_NAME" ] && [ ! -z "$SERVER_PORT" ];
    then
        CAN_CONFIGURE=true;
    else
        if [ ! -z "$SERVER" ];
        then
            CAN_CONFIGURE=true;

            readarray -t SITES < <($DIR_SCRIPTS/split-to-lines.sh "," "$SERVER,");

            SITE_REGEX="^[a-zA-Z0-9\.-_]+(|/php[0578]|/wordpress)$";
            for SITE in ${SITES[@]};
            do
                if [ ! -z "$SITE" ] && [[ ! "${SITE}" =~ ${SITE_REGEX} ]];
                then
                    printf "INVALID SITE VALUE: $SITE\n";
                    CAN_CONFIGURE=false;
                    break;
                fi
            done
        else
            CAN_CONFIGURE=false;
        fi
    fi

    if [ "$CAN_CONFIGURE" = false ];
    then
        printf "The directory name or address and port of the service was not informed.\n";
        printf "For directory name you can use PHP version as \"/php5\", \"/php7\" or \"/php8\" (default) or \"/php0\" to disable it.\n";
        printf "Use \"/wordpress\" to configure for it..\n";
        printf "Set variable to one of the two below:\n";
        printf "  HOST${INDEX_HOST}_LOCATION=<directory1>/php0,<directory2>/php5,<directory3>/php8/wordpress,<directory4>\n";
        printf "  HOST${INDEX_HOST}_LOCATION=<server name>:<port number>\n";
    fi

    if [ "$CAN_CONFIGURE" = true ];
    then
        printf "\n";
        
        printf "    Total url:      ${#URLS[@]}\n";        

        INDEX_URL=0;
        for URL in ${URLS[@]};
        do
            INDEX_URL=$((INDEX_URL + 1));

            PADDING=$( test $INDEX_URL -lt 10 && echo " " || echo "");
            printf "    - Url $INDEX_URL:$PADDING       $URL\n";
        done

        if [ ! -z "${SITES[0]}" ];
        then
            SITES_DIRECTORY=();
            SITES_FEATURE_PHP=();
            SITES_FEATURE_WORDPRESS=();

            INDEX_SITE=0;
            for SITE in ${SITES[@]};
            do
                readarray -t SITE_PARTS < <($DIR_SCRIPTS/split-to-lines.sh "/" "$SITE/");

                SITES_DIRECTORY[$INDEX_SITE]=${SITE_PARTS[0]};

                SITES_FEATURE_PHP[$INDEX_SITE]="php8";
                if [[ "$SITE" =~ "/php0" ]];
                then
                    SITES_FEATURE_PHP[$INDEX_SITE]="php0";
                fi
                if [[ "$SITE" =~ "/php5" ]];
                then
                    SITES_FEATURE_PHP[$INDEX_SITE]="php5";
                fi
                if [[ "$SITE" =~ "/php7" ]];
                then
                    SITES_FEATURE_PHP[$INDEX_SITE]="php7";
                fi

                if [[ "$SITE" =~ "/wordpress" ]];
                then
                    SITES_FEATURE_WORDPRESS[$INDEX_SITE]="wordpress";
                else
                    SITES_FEATURE_WORDPRESS[$INDEX_SITE]="";
                fi

                printf "    Site $((INDEX_SITE + 1))\n";
                printf "    - Directory:    ${SITES_DIRECTORY[$INDEX_SITE]}\n";
                printf "    - PHP Version:  ${SITES_FEATURE_PHP[$INDEX_SITE]}\n";
                printf "    - Wordpress:    $( (test ! -z "${SITES_FEATURE_WORDPRESS[$INDEX_SITE]}" && echo "yes" ) || echo "no" )\n";

                INDEX_SITE=$((INDEX_SITE + 1));
            done
        else
            printf "    Reverse proxy\n";
            printf "    - Server name:  $SERVER_NAME\n";
            printf "    - Server port:  $SERVER_PORT\n";
        fi

        printf "    Let's Encrypt:  $SSL_ENABLE\n";
        if [ "$SSL_ENABLE" = true ];
        then
            printf "    - Email:        $SSL_EMAIL\n";
        fi
        
        printf "    Authentication: $AUTH_ENABLE\n";
        if [ "$AUTH_ENABLE" = true ];
        then
            INDEX_USER=0;
            readarray -t AUTH_LIST < <($DIR_SCRIPTS/split-to-lines.sh "," $AUTH_INFO);    
            for AUTH in ${AUTH_LIST[@]};
            do
                INDEX_USER=$((INDEX_USER + 1));
                readarray -t USER_PASS < <($DIR_SCRIPTS/split-to-lines.sh "=" $AUTH);

                USER=${USER_PASS[0]};
                PASS=${USER_PASS[1]};

                AUTH_USERS+=($USER);
                AUTH_PASSWORDS+=($PASS);

                PADDING=$( test $INDEX_USER -lt 10 && echo " " || echo "");
                printf "    - User $INDEX_USER:$PADDING      $USER\n";
            done

            AUTH_ENABLE=$( (test -n "${AUTH_USERS[0]}" && echo true) || echo false );
        fi
        printf "\n";

        FILE_CONF="$DIR_CONF_D/$PREFIX_SITE${URLS[0]}.conf";
        FILE_PASSWD="$FILE_CONF.htpasswd";

        rm -f $FILE_CONF;
        rm -f $FILE_PASSWD;

        DIR_CERTIFICATES_HOST="$DIR_CERTIFICATES/${URLS[0]}";
        DIR_CERTIFICATES_HOST_FULLCHAIN="$DIR_CERTIFICATES_HOST/fullchain.pem";
        DIR_CERTIFICATES_HOST_PRIVKEY="$DIR_CERTIFICATES_HOST/privkey.pem";

        if [ "$SSL_ENABLE" = true ];
        then
            if [ ! -s "$DIR_CERTIFICATES_HOST_FULLCHAIN" ] || [ ! -s "$DIR_CERTIFICATES_HOST_PRIVKEY" ];
            then

                printf "Requesting certificate to Let's Encrypt.\n";

                touch $FILE_CONF;
                mkdir -p $DIR_CERTBOT_WEBROOT;
                chmod -R 777 $DIR_CERTBOT_WEBROOT;
                
                SITE_DIR_NAME="${URLS[0]}-letsencrypt";
                echo "server {" >> $FILE_CONF;
                echo "    listen                       80;" >> $FILE_CONF;
                echo "    listen                       [::]:80;" >> $FILE_CONF;
                echo "    server_name                  $URLS_ALL;" >> $FILE_CONF;
                echo "    access_log                   /var/log/nginx/${SITE_DIR_NAME}-80-access.log;" >> $FILE_CONF;
                echo "    error_log                    /var/log/nginx/${SITE_DIR_NAME}-80-error.log;" >> $FILE_CONF;
                echo "    location / {" >> $FILE_CONF;
                echo "        root                     $DIR_CERTBOT_WEBROOT/;" >> $FILE_CONF;
                echo "    }" >> $FILE_CONF;
                echo "}" >> $FILE_CONF;

                $NGINX_EXECUTABLE -s reload;
                sleep 1;

                CERTBOT_ARG_DOMAINS=$(IFS="§"; echo "${URLS[*]}");
                CERTBOT_ARG_DOMAINS="-d ${CERTBOT_ARG_DOMAINS//§/" -d "}";
                CERTBOT_ARG="certonly -n --agree-tos --webroot -w $DIR_CERTBOT_WEBROOT -m $SSL_EMAIL --cert-name ${URLS[0]} $CERTBOT_ARG_DOMAINS";
                CERTBOT_COMMAND="$CERTBOT_EXECUTABLE $CERTBOT_ARG";
                printf "$CERTBOT_COMMAND\n";
                $CERTBOT_COMMAND;

                DIR_CERTIFICATES_CERTBOT="$DIR_CERTBOT_CERTIFICATES/${URLS[0]}";
                mkdir -p $DIR_CERTIFICATES_HOST;
                cp $DIR_CERTIFICATES_CERTBOT/* $DIR_CERTIFICATES_HOST/;

                rm -R $DIR_CERTBOT_WEBROOT;
                rm -f $FILE_CONF;

                date -u >> $DIR_CERTIFICATES_HOST/DATETIME;

                printf "Certificates files created:\n";
            else
                printf "Certificates files already exist:\n";
            fi
            $LS -d $DIR_CERTIFICATES_HOST/*;
        fi

        if [ "$AUTH_ENABLE" = true ];
        then
            printf "Configuring access control.\n";
            
            touch $FILE_PASSWD;
            chown root:$NGINX_USER $FILE_PASSWD;
            chmod 640 $FILE_PASSWD;

            INDEX_AUTH=0;
            for AUTH_USER in "${AUTH_USERS[@]}"
            do
                AUTH_PASS=${AUTH_PASSWORDS[$INDEX_AUTH]};
                echo "$AUTH_PASS" | htpasswd -i $FILE_PASSWD "$AUTH_USER";
                INDEX_AUTH=$((INDEX_AUTH + 1));
            done
        else
            printf "No access control configured.\n";
        fi

        touch $FILE_CONF;
        
        if [ "$SSL_ENABLE" = true ];
        then
            SITE_DIR_NAME="${URLS[0]}-$DEFAULT_SERVER_NAME";
            echo "server {" >> $FILE_CONF;
            echo "    listen                                 80;" >> $FILE_CONF;
            echo "    listen                                 [::]:80;" >> $FILE_CONF;
            echo "    server_name                            $URLS_ALL;" >> $FILE_CONF;
            echo "    access_log                             /var/log/nginx/${SITE_DIR_NAME}-80-access.log;" >> $FILE_CONF;
            echo "    error_log                              /var/log/nginx/${SITE_DIR_NAME}-80-error.log;" >> $FILE_CONF;
            echo "    return                                 301 https://\$host\$request_uri;" >> $FILE_CONF;
            echo "}" >> $FILE_CONF;
            echo "" >> $FILE_CONF;
        fi

        echo "server {" >> $FILE_CONF;

        if [ "$SSL_ENABLE" = true ];
        then
            echo "    listen                                 443 ssl;" >> $FILE_CONF;
            echo "    listen                                 [::]:443 ssl;" >> $FILE_CONF;
            echo "" >> $FILE_CONF;
            SITE_PORT="443";
        else
            echo "    listen                                 80;" >> $FILE_CONF;
            echo "    listen                                 [::]:80;" >> $FILE_CONF;
            echo "" >> $FILE_CONF;
            SITE_PORT="80";
        fi

        echo "    server_name                            $URLS_ALL;" >> $FILE_CONF;
        echo "" >> $FILE_CONF;

        SITE_DIR_NAME="${URLS[0]}-$DEFAULT_SERVER_NAME";
        echo "    access_log                             /var/log/nginx/${SITE_DIR_NAME}-$SITE_PORT-access.log;" >> $FILE_CONF;
        echo "    error_log                              /var/log/nginx/${SITE_DIR_NAME}-$SITE_PORT-error.log;" >> $FILE_CONF;
        echo "" >> $FILE_CONF;

        TEMPLATE_CONF_FILE="server-${URLS[0]}.conf.part";
        if [ ! -f "$DIR_CONF_D_TEMPLATES/$TEMPLATE_CONF_FILE$SUFFIX_TEMPLATE" ];
        then
            echo "# This file will be inserted into section: server { <inserted here> }" > $DIR_CONF_D/$TEMPLATE_CONF_FILE;
            cp -f $DIR_CONF_D/$TEMPLATE_CONF_FILE $DIR_CONF_D_TEMPLATES/$TEMPLATE_CONF_FILE$SUFFIX_TEMPLATE;
        fi
        echo "    include                                $DIR_CONF_D/server-common.conf.part;" >> $FILE_CONF;
        echo "    include                                $DIR_CONF_D/$TEMPLATE_CONF_FILE;" >> $FILE_CONF;
        echo "" >> $FILE_CONF;

        if [ -n "${SITES[0]}" ];
        then
            if [ ! -d "$DIR_DEFAULT_SERVER" ];
            then
                printf "Creating empty index.html file to be used as default_server.\n";
                mkdir -p $DIR_DEFAULT_SERVER;
                echo "" > $DIR_DEFAULT_SERVER/index.html;
                $LS $DIR_DEFAULT_SERVER/index.html;
            fi
            echo "    root                                   $DIR_DEFAULT_SERVER/;" >> $FILE_CONF;

            if [ "$AUTH_ENABLE" = true ];
            then
                echo "    auth_basic                             \"Enter your access credentials to enter ${URLS[0]}\";" >> $FILE_CONF;
                echo "    auth_basic_user_file                   $FILE_PASSWD;" >> $FILE_CONF;
                echo "" >> $FILE_CONF;
            fi

            if [ "${SITES_FEATURE_PHP[$INDEX_SITE]}" == "php0" ];
            then
                echo "    index                                  index.html index.htm;" >> $FILE_CONF;
            else
                echo "    index                                  index.html index.htm index.php;" >> $FILE_CONF;
            fi

            INDEX_SITE=0;
            for SITE in ${SITES[@]};
            do
                SITE_LOCATION=${SITES_DIRECTORY[$INDEX_SITE]};
                SITE_DIR_NAME=${URLS[0]}$( (test ! -z "$SITE_LOCATION" && echo "-$SITE_LOCATION") || echo "" );
                SITE_LOCATION_PATH="$DIR_SITES/$SITE_DIR_NAME/$DIR_SITES_ROOT";
                SITE_LOCATION_SLASH=$( echo /$SITE_LOCATION/ | sed 's/\/\//\//' );

                echo "" >> $FILE_CONF;
                echo "    location /$SITE_LOCATION {" >> $FILE_CONF;
                echo "        alias                              $SITE_LOCATION_PATH/;" >> $FILE_CONF;
                echo "" >> $FILE_CONF;
                echo "        access_log                         /var/log/nginx/${SITE_DIR_NAME}-$SITE_PORT-access.log;" >> $FILE_CONF;
                echo "        error_log                          /var/log/nginx/${SITE_DIR_NAME}-$SITE_PORT-error.log;" >> $FILE_CONF;
                echo "" >> $FILE_CONF;

                TEMPLATE_CONF_FILE="location-$SITE_DIR_NAME.conf.part";
                if [ ! -f "$DIR_CONF_D_TEMPLATES/$TEMPLATE_CONF_FILE$SUFFIX_TEMPLATE" ];
                then
                    echo "# This file will be inserted into section: server { location /directory { <inserted here> } }" > $DIR_CONF_D/$TEMPLATE_CONF_FILE;
                    cp -f $DIR_CONF_D/$TEMPLATE_CONF_FILE $DIR_CONF_D_TEMPLATES/$TEMPLATE_CONF_FILE$SUFFIX_TEMPLATE;
                fi
                echo "        include                            $DIR_CONF_D/location-common.conf.part;" >> $FILE_CONF;
                echo "        include                            $DIR_CONF_D/$TEMPLATE_CONF_FILE;" >> $FILE_CONF;
                echo "" >> $FILE_CONF;

                if [ ! -z "${SITES_FEATURE_WORDPRESS[$INDEX_SITE]}" ];
                then
                    echo "        if (!-e \$request_filename) {" >> $FILE_CONF;
                    echo "            rewrite ^/(.*)$ ${SITE_LOCATION_SLASH}index.php?\$1;" >> $FILE_CONF;
                    echo "        }" >> $FILE_CONF;
                    echo "" >> $FILE_CONF;
                fi

                if [ "${SITES_FEATURE_PHP[$INDEX_SITE]}" != "php0" ];
                then
                    echo "        location ~ [^/]\.php(/|\$) {" >> $FILE_CONF;
                    echo "            fastcgi_split_path_info        ^(.+?\.php)(/.*)\$;" >> $FILE_CONF;
                    echo "            fastcgi_pass                   ${SITES_FEATURE_PHP[$INDEX_SITE]}:9000;" >> $FILE_CONF;
                    echo "            fastcgi_index                  index.php;" >> $FILE_CONF;
                    echo "            include                        fastcgi_params;" >> $FILE_CONF;
                    echo "            fastcgi_param                  SCRIPT_FILENAME \$request_filename;" >> $FILE_CONF;
                    echo "            fastcgi_intercept_errors       on;" >> $FILE_CONF;
                    echo "        }" >> $FILE_CONF;
                fi

                echo "    }" >> $FILE_CONF;

                if [ ! -d "$SITE_LOCATION_PATH" ];
                then
                    printf "Creating sample index.html file for /$SITE_LOCATION location.\n";
                    mkdir -p $SITE_LOCATION_PATH;
                    echo "${URLS[0]}/$SITE_NAME" > $SITE_LOCATION_PATH/index.html;
                    $LS $SITE_LOCATION_PATH/index.html;
                fi

                INDEX_SITE=$((INDEX_SITE + 1));
            done
        else
            echo "    location / {" >> $FILE_CONF;
            echo "        proxy_pass                         http://$SERVER_NAME:$SERVER_PORT;" >> $FILE_CONF;
            echo "" >> $FILE_CONF;

            if [ "$AUTH_ENABLE" = true ];
            then
                echo "        auth_basic                         \"Enter your access credentials to enter ${URLS[0]}\";" >> $FILE_CONF;
                echo "        auth_basic_user_file               $FILE_PASSWD;" >> $FILE_CONF;
                echo "" >> $FILE_CONF;
            fi

            TEMPLATE_CONF_FILE="location-${URLS[0]}.conf.part";
            if [ ! -f "$DIR_CONF_D_TEMPLATES/$TEMPLATE_CONF_FILE$SUFFIX_TEMPLATE" ];
            then
                echo "# This file will be inserted into section: server { location / { <inserted here> } }" > $DIR_CONF_D/$TEMPLATE_CONF_FILE;
                cp -f $DIR_CONF_D/$TEMPLATE_CONF_FILE $DIR_CONF_D_TEMPLATES/$TEMPLATE_CONF_FILE$SUFFIX_TEMPLATE;
            fi
            echo "" >> $FILE_CONF;
            echo "        include                            $DIR_CONF_D/location-common.conf.part;" >> $FILE_CONF;
            echo "        include                            $DIR_CONF_D/$TEMPLATE_CONF_FILE;" >> $FILE_CONF;
            echo "" >> $FILE_CONF;

            echo "        proxy_http_version                 1.1;" >> $FILE_CONF;
            echo "        proxy_cache_bypass                 \$http_upgrade;" >> $FILE_CONF;
            echo "        proxy_set_header Upgrade           \$http_upgrade;" >> $FILE_CONF;
            echo "        proxy_set_header Connection        \"upgrade\";" >> $FILE_CONF;
            echo "        proxy_set_header Host              \$host;" >> $FILE_CONF;
            echo "        proxy_set_header X-Real-IP         \$remote_addr;" >> $FILE_CONF;
            echo "        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;" >> $FILE_CONF;
            echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> $FILE_CONF;
            echo "        proxy_set_header X-Forwarded-Host  \$host;" >> $FILE_CONF;
            echo "        proxy_set_header X-Forwarded-Port  \$server_port;" >> $FILE_CONF;
            echo "    }" >> $FILE_CONF;
        fi

        if [ "$SSL_ENABLE" = true ];
        then
            echo "" >> $FILE_CONF;
            echo "    ssl_certificate                        $DIR_CERTIFICATES_HOST_FULLCHAIN;" >> $FILE_CONF;
            echo "    ssl_certificate_key                    $DIR_CERTIFICATES_HOST_PRIVKEY;" >> $FILE_CONF;
        fi

        if [ ! -z "$NGINX_CONFIG" ];
        then
            echo "" >> $FILE_CONF;
            echo "    $NGINX_CONFIG" >> $FILE_CONF;
        fi

        echo "}" >> $FILE_CONF;
        echo "" >> $FILE_CONF;

        FILE_CONF_TEMPLATE="$DIR_CONF_D_TEMPLATES/$( basename $FILE_CONF)$SUFFIX_TEMPLATE";
        if [ ! -f $FILE_CONF_TEMPLATE ] || [ "" = "$(cat $FILE_CONF_TEMPLATE | grep -v -s '^#' | grep -v -s '^\s*$')" ];
        then
            echo "#Uncomment to use this configuration file" > $FILE_CONF_TEMPLATE;
            echo "" >> $FILE_CONF_TEMPLATE;
            cat $FILE_CONF >> $FILE_CONF_TEMPLATE
            sed -i 's/^/#/g' $FILE_CONF_TEMPLATE;

            printf "Configuration file created: $FILE_CONF\n";
        else
            printf "Using template configuration file created: $FILE_CONF_TEMPLATE\n";
        fi
    else
        printf "Configuration aborted.\n";
    fi

    INDEX_HOST=$((INDEX_HOST + 1));
done

if [ "$INDEX_HOST" = 1 ];
then
    printf "No reverse proxy or website settings were found on the environment variables.\n";
fi

ls -d1 $DIR_SCRIPTS/nginx-*.part$SUFFIX_TEMPLATE | \
    sed 's/\/.*\///' | \
    xargs -I {} cp -u $DIR_SCRIPTS/{} $DIR_CONF_D_TEMPLATES/{};
ls -d1 $DIR_SCRIPTS/nginx-*.part$SUFFIX_TEMPLATE | \
    sed 's/\/.*\/nginx-//' | \
    xargs -I {} mv $DIR_CONF_D_TEMPLATES/nginx-{} $DIR_CONF_D_TEMPLATES/{};
printf "Template part configuration files was created (if not exist).\n";
$LS $DIR_CONF_D_TEMPLATES/*.part$SUFFIX_TEMPLATE;

printf "Tip: Use files $DIR_CONF_D_TEMPLATES/*$SUFFIX_TEMPLATE to make the files in the $DIR_CONF_D directory with replacement of environment variables with their values.\n";

ls -1 ${DIR_CONF_D_TEMPLATES}/ | \
    grep "^site-.*$SUFFIX_TEMPLATE$" | \
    xargs -I {} echo ${DIR_CONF_D_TEMPLATES}/{} | \
    xargs -I {} sh -c '( test "" = "$(cat {} | grep -v ^# | grep -v ^\s*$)" && echo echo Ignoring empty template: {} && mv {} {}-isEmpty ) || echo ' | \
    sh;

$DIR_SCRIPTS/envsubst-files.sh "$SUFFIX_TEMPLATE" "$DIR_CONF_D_TEMPLATES" "$DIR_CONF_D";

ls -1 ${DIR_CONF_D_TEMPLATES}/ | \
    grep "$SUFFIX_TEMPLATE-isEmpty$" | \
    xargs -I {} echo ${DIR_CONF_D_TEMPLATES}/{} | \
    xargs -I {} echo mv {} {} | \
    sed 's/-isEmpty$//' | \
    sh;

printf "Starting nginx.\n";

$NGINX_EXECUTABLE -s stop;
sleep 1;
$NGINX_EXECUTABLE -g "daemon off;" ${NGINX_ARGS};
