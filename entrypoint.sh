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
DIR_CONF="/etc/nginx";
DIR_CONF_BACKUP="$DIR_CONF.original";
DIR_CONF_DOCKER="$DIR_CONF.conf";
DIR_CONF_D="$DIR_CONF/conf.d";
DIR_CONF_D_TEMPLATES="$DIR_CONF.templates";
DIR_CERTIFICATES="$DIR_CONF.certificates";
DIR_CERTIFICATES_DEFAULT="$DIR_CERTIFICATES/default_server";
FILE_CERTIFICATE_DEFAULT="$DIR_CERTIFICATES_DEFAULT/autosigned";
DIR_SCRIPTS="${DIR_SCRIPTS:-/root}";
DIR_SITES="/home";
DIR_SITES_ROOT="www";
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
           xargs -I {} mv $DIR_CONF_D_TEMPLATES/{} $DIR_CONF_D_TEMPLATES/{}$SUFFIX_TEMPLATE;

        FILE_CONF="$DIR_CONF_D_TEMPLATES/default.conf$SUFFIX_TEMPLATE";
        printf "Adjusting default configuration file template: $(basename $FILE_CONF)\n";
        echo "" >> $FILE_CONF;
        echo "server {" >> $FILE_CONF;
        echo "    listen              443 ssl;" >> $FILE_CONF;
        echo "    listen              [::]:443 ssl;" >> $FILE_CONF;
        echo "    ssl_certificate     $FILE_CERTIFICATE_DEFAULT.crt;" >> $FILE_CONF;
        echo "    ssl_certificate_key $FILE_CERTIFICATE_DEFAULT.key;" >> $FILE_CONF;
        echo "    return              301 http://\$host\$request_uri;" >> $FILE_CONF;
        echo "}" >> $FILE_CONF;

    fi
    $LS -Ad $DIR_CONF_D_TEMPLATES/*;

    printf "Configured directories:\n";

    chown -R $USER:$USER $DIR_CONF_BACKUP;
    chown -R $USER:$USER $DIR_CONF_DOCKER;
    chown -R $USER:$USER $DIR_CONF_D_TEMPLATES;
    
    $LS -d $DIR_CONF $DIR_CONF_BACKUP $DIR_CONF_DOCKER $DIR_CONF_D_TEMPLATES;
else
    printf "This is NOT the first run.\n";

    $NGINX_EXECUTABLE;
    sleep 1;
fi

printf "Tip: Use files $DIR_CONF_D_TEMPLATES/*$SUFFIX_TEMPLATE to make the files in the $DIR_CONF_D directory with replacement of environment variables with their values.\n";

$DIR_SCRIPTS/envsubst-files.sh "$SUFFIX_TEMPLATE" "$DIR_CONF_D_TEMPLATES" "$DIR_CONF_D";

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

    printf "Auto-signed certificate files created:\n";
else
    printf "Auto-signed certificate files already exist:\n";
fi
$LS -d $DIR_CERTIFICATES_HOST/*;

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

    SSL_ENABLE=$( (test -n "$SSL_EMAIL" && echo true) || echo false )
    AUTH_ENABLE=$( (test -n "$AUTH_INFO" && echo true) || echo false );

    AUTH_USERS=();
    AUTH_PASSWORDS=();

    readarray -t SERVER_PARTS < <($DIR_SCRIPTS/split-to-lines.sh ":" "$SERVER:");
    SITE_NAME="";
    SERVER_NAME=${SERVER_PARTS[0]};
    SERVER_PORT=${SERVER_PARTS[1]};    

    CAN_CONFIGURE=true;

    if [ -z "$SERVER_NAME" ] || [ -z "$SERVER_PORT" ];
    then
        SITE_REGEX="^[\w\.-_]+$";
        if [[ "${SERVER}" =~ ${pattern} ]];
        then
            SITE_NAME="$SERVER";
            SITE_LOCATION="$DIR_SITES/$SITE_NAME/$DIR_SITES_ROOT";
        else
            printf "The directory name or address and port of the service was not informed.\n";
            printf "Set variable to one of the two below:\n";
            printf "  HOST${INDEX_HOST}_LOCATION=<directory name>\n";
            printf "  HOST${INDEX_HOST}_LOCATION=<server name>:<port number>\n";
            CAN_CONFIGURE=false;
        fi
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

        if [ -n "$SITE_NAME" ];
        then
            printf "    Site\n";
            printf "    - Name:         $SITE_NAME\n";
            printf "    - Root path:    $SITE_LOCATION\n";
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

        FILE_CONF="$DIR_CONF_D/${URLS[0]}.conf";
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
                
                echo "server {" >> $FILE_CONF;
                echo "    listen                       80;" >> $FILE_CONF;
                echo "    listen                       [::]:80;" >> $FILE_CONF;
                echo "    server_name                  $URLS_ALL;" >> $FILE_CONF;        
                echo "    location / {" >> $FILE_CONF;
                echo "        root                     $DIR_CERTBOT_WEBROOT;" >> $FILE_CONF;
                echo "    }" >> $FILE_CONF;
                echo "}" >> $FILE_CONF;

                $NGINX_EXECUTABLE -s reload;
                sleep 1;

                CERTBOT_ARG_DOMAINS=$(IFS="§"; echo "${URLS[*]}");
                CERTBOT_ARG_DOMAINS="-d ${CERTBOT_ARG_DOMAINS/§/" -d "}";
                CERTBOT_ARG="certonly -n --agree-tos --webroot -w $DIR_CERTBOT_WEBROOT -m $SSL_EMAIL --cert-name ${URLS[0]} $CERTBOT_ARG_DOMAINS";
                CERTBOT_COMMAND="$CERTBOT_EXECUTABLE $CERTBOT_ARG";
                printf "$CERTBOT_COMMAND\n";
                $CERTBOT_COMMAND;

                DIR_CERTIFICATES_CERTBOT="$DIR_CERTBOT_CERTIFICATES/${URLS[0]}";
                mkdir -p $DIR_CERTIFICATES_HOST;
                cp $DIR_CERTIFICATES_CERTBOT/* $DIR_CERTIFICATES_HOST/;

                rm -R $DIR_CERTBOT_WEBROOT;
                rm -f $FILE_CONF;

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
            echo "server {" >> $FILE_CONF;
            echo "    listen                                 80;" >> $FILE_CONF;
            echo "    listen                                 [::]:80;" >> $FILE_CONF;
            echo "    server_name                            $URLS_ALL;" >> $FILE_CONF;
            echo "    return                                 301 https://\$host\$request_uri;" >> $FILE_CONF;
            echo "}" >> $FILE_CONF;
            echo "" >> $FILE_CONF;
        fi

        echo "server {" >> $FILE_CONF;

        if [ "$SSL_ENABLE" = true ];
        then
            echo "    listen                                 443 ssl;" >> $FILE_CONF;
            echo "    listen                                 [::]:443 ssl;" >> $FILE_CONF;
        else
            echo "    listen                                 80;" >> $FILE_CONF;
            echo "    listen                                 [::]:80;" >> $FILE_CONF;
        fi

        echo "    server_name                            $URLS_ALL;" >> $FILE_CONF;
        echo "" >> $FILE_CONF;

        if [ -n "$SITE_NAME" ];
        then
            echo "    root                                   $SITE_LOCATION;" >> $FILE_CONF;
            if [ ! -d "$SITE_LOCATION" ];
            then
                mkdir -p $SITE_LOCATION;
                echo $SITE_NAME > "$SITE_LOCATION/index.html";
            fi
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
        echo "}" >> $FILE_CONF;
        echo "" >> $FILE_CONF;

        printf "Configuration file created: $FILE_CONF\n";

    else
        printf "Configuration aborted.\n";
    fi

    INDEX_HOST=$((INDEX_HOST + 1));
done

if [ "$INDEX_HOST" = 1 ];
then
    printf "No reverse proxy settings were found on the environment variables.\n";
fi

printf "Starting nginx.\n";

$NGINX_EXECUTABLE -s stop;
sleep 1;
$NGINX_EXECUTABLE -g "daemon off;" ${NGINX_ARGS};
