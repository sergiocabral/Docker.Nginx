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

NGINX_EXECUTABLE=$(which nginx || echo "");
SUFFIX_TEMPLATE=".template";
DIR_CONF="/etc/nginx";
DIR_CONF_BACKUP="$DIR_CONF.original";
DIR_CONF_DOCKER="$DIR_CONF.conf";
DIR_CONF_D="$DIR_CONF/conf.d";
DIR_CONF_D_TEMPLATES="$DIR_CONF.templates";
DIR_SCRIPTS="${DIR_SCRIPTS:-/root}";
LS="ls --color=auto -CFl";

if [ ! -e "$NGINX_EXECUTABLE" ];
then
    printf "Nginx is not installed.\n" >> /dev/stderr;
    exit 1;
fi

IS_FIRST_CONFIGURATION=$((test ! -d $DIR_CONF_BACKUP && echo true) || echo false);

if [ $IS_FIRST_CONFIGURATION = true ];
then
    printf "This is the FIRST RUN.\n";
    
    printf "Running nginx for the first time.\n";

    USER=root;

    DIR="/var/log/nginx";   mkdir -p $DIR && chmod -R 755 $DIR && chown -R $USER:$USER $DIR;
    DIR="/run/nginx";       mkdir -p $DIR && chmod -R 755 $DIR && chown -R $USER:$USER $DIR;

    $NGINX_EXECUTABLE;
    sleep 1;
    $NGINX_EXECUTABLE -s stop;
    sleep 1;

    printf "Configuring directories.\n";

    mkdir -p $DIR_CONF_BACKUP && cp -R $DIR_CONF/* $DIR_CONF_BACKUP;
    mkdir -p $DIR_CONF_DOCKER && cp -R $DIR_CONF/* $DIR_CONF_DOCKER;
    rm -R $DIR_CONF;
    ln -s $DIR_CONF_DOCKER $DIR_CONF;

    mkdir -p $DIR_CONF_D_TEMPLATES;

    if [ -d "$DIR_CONF_D_TEMPLATES" ] && [ ! -z "$(ls -A $DIR_CONF_D_TEMPLATES)" ];
    then
        printf "Warning: The $DIR_CONF_D_TEMPLATES directory already existed and will not have its content overwritten.\n";
    else
        printf "Creating file templates in $DIR_CONF_D_TEMPLATES\n";

        cp -R $DIR_CONF_D/* $DIR_CONF_D_TEMPLATES;
        ls -1 $DIR_CONF_D_TEMPLATES | \
           grep -v $SUFFIX_TEMPLATE | \
           xargs -I {} mv $DIR_CONF_D_TEMPLATES/{} $DIR_CONF_D_TEMPLATES/{}$SUFFIX_TEMPLATE;    
    fi
    $LS -Ad $DIR_CONF_D_TEMPLATES/*;

    printf "Configured directories:\n";

    chmod -R 755 $DIR_CONF_BACKUP       && chown -R $USER:$USER $DIR_CONF_BACKUP;
    chmod -R 755 $DIR_CONF_DOCKER       && chown -R $USER:$USER $DIR_CONF_DOCKER;
    chmod -R 755 $DIR_CONF_D_TEMPLATES  && chown -R $USER:$USER $DIR_CONF_D_TEMPLATES;
    
    $LS -d $DIR_CONF $DIR_CONF_BACKUP $DIR_CONF_DOCKER $DIR_CONF_D_TEMPLATES;
else
    printf "This is NOT the first run.\n";
fi

printf "Tip: Use files $DIR_CONF_D_TEMPLATES/*$SUFFIX_TEMPLATE to make the files in the $DIR_CONF_D directory with replacement of environment variables with their values.\n";

$DIR_SCRIPTS/envsubst-files.sh "$SUFFIX_TEMPLATE" "$DIR_CONF_D_TEMPLATES" "$DIR_CONF_D";

INDEX_HOST=1;
while [ ! -z "$(VAR_NAME="HOST${INDEX_HOST}_URL"; echo "${!VAR_NAME}")" ];
do
    VAR_NAME="HOST${INDEX_HOST}_URL";
    URL=${!VAR_NAME};
    
    VAR_NAME="HOST${INDEX_HOST}_SSL_EMAIL";
    SSL_EMAIL=${!VAR_NAME};

    VAR_NAME="HOST${INDEX_HOST}_AUTH";
    AUTH_INFO=${!VAR_NAME};

    SSL_ENABLE=$( (test ! -z "$SSL_EMAIL" && echo true) || echo false )
    AUTH_ENABLE=$( (test ! -z "$AUTH_INFO" && echo true) || echo false );

    AUTH_USERS=();
    AUTH_PASSWORDS=();
    
    printf "Configuring reverse proxy for host $INDEX_HOST.\n";
    printf "\n";
    printf "    Url:            $URL\n";
    
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

            PADDING=$( test $INDEX_USER -lt 10 && echo " ");
            printf "    - User $INDEX_USER:$PADDING      $USER\n";
        done
    fi

    printf "\n";
    printf "Doing.\n";
    printf "Done.\n";

    INDEX_HOST=$((INDEX_HOST + 1));
done

if [ "$INDEX_HOST" = 1 ];
then
    printf "No reverse proxy settings were found on the environment variables.\n";
fi

printf "Starting nginx.\n";

$NGINX_EXECUTABLE -g "daemon off;" ${NGINX_ARGS};
