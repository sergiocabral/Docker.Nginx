# Docker.Nginx

Webserver using the Nginx application. With the possibility to configure Let's Encrypt SSL certificates using the Certbot application.

## Configuration

It is possible to configure the services through the Nginx `*.conf` files.

It is possible to use template `*.conf.template` files to generate the final `.conf` files with the appropriate substitutions of the values of the environment variables.

If you want, configure a website or reverse proxy of your services using only environment variables.

## Environment Variables

**Configuring your services or websites:**

`HOST1_URL` = `domain1.com domain1-secondary.com domain1-other.com`

- Mandatory value.
- Inform the url that will be exposed on the internet to access your service.
- You can enter one or more separated by space.
- Each url entered here is linked to the SSL certificate, if it is generated.

`HOST1_LOCATION` = `10.0.0.10:5555` or `website-directory-name`

- Mandatory value.
- For reverse proxy use:
  - Service access name, either hostname or IP.
  - It is mandatory to inform the port (after the colon) of the service, which in turn will be exposed as an HTTP or HTTPS port.
- For website use:
  - Directory name with characters set `a-z`, `0-9`, `-`, `.`.

`HOST1_AUTH` = `username1=password1,username2=password2,username3=password3`

- Optional value.
- When informed, access to the service will be validated by user and password via HTTP Basic Authentication.
- Inform users and their passwords in the example format.

`HOST1_SSL_EMAIL` = `email@domain1.com`

- Optional value.
- If this field is not informed, a Let's Encrypt SSL certificate will not be registered for the domains informed in the first field above.
- If an e-mail is informed, Let's Encrypt will be asked for a certificate for the informed domains that will in turn be associated with this e-mail.

**Configuring more than one:**

As you should see the names of the environment variables above are prefixed with `HOST1`. To register other services sequentially use `HOST2`, `HOST3` and so on.

If your sequence happens to skip a number, everything else will be ignored.

For example, if you register `HOST1`, `HOST2`, `HOST4`, `HOST5`, `HOST6`, only the first two will be considered.

If the first on the list is `HOST0` it will not be considered.

If the first on the list is `HOST2`, nothing else will be considered.

## Suggested Directory Volumes

`/etc/nginx.templates`

- Use files `/etc/squid.templates/*.template` to make the files in the `/etc/nginx/conf.d` directory with replacement of environment variables with their values.

`/etc/nginx.conf`

- Configuration directory used by the Nginx application. All configuration files are here.
- The default `/etc/nginx/` directory is a symbolic link that points to this directory.

`/etc/nginx.certificates`

- Directory where Let's Encrypt certificates generated by the Certbot application will be saved.
- Automatic reverse proxy settings using environment variables refer to certificates in this directory.

`/home`

- Host directories of each websites.

`/var/log/nginx`

- Log files.

`/var/lib/nginx/tmp`

- Temporary files.

## Exposed Port

Automatic reverse proxy settings using environment variables register as HTTP and HTTPS ports 80 and 443 respectively.

## Example for *docker-compose.yml*

```
version: "3.3"
services:
  proxy:
    image: sergiocabral/nginx
    ports:
      - 80:80
      - 443:443
    volumes:
      - /docker-volumes/nginx/templates:/etc/nginx.templates
      - /docker-volumes/nginx/certificates:/etc/nginx.certificates
      - /docker-volumes/nginx/conf:/etc/nginx.conf
      - /docker-volumes/nginx/log:/var/log/nginx
      - /docker-volumes/nginx/temp:/var/lib/nginx/tmp/
    environment:

      # Reverse proxy. Multiple urls. With HTTP authentication. With SSL certificate.
      - HOST1_URL=domain1.com domain1-secondary.com domain1-other.com
      - HOST1_LOCATION=10.0.0.11:5555
      - HOST1_AUTH=username1=password1,username2=password2,username3=password3
      - HOST1_SSL_EMAIL = email@domain1.com

      # Website. Single url. Without HTTP authentication. Without SSL certificate.
      - HOST2_URL=domain2.com
      - HOST2_LOCATION=my-website

      # Website. Without HTTP authentication. With SSL certificate.
      - HOST3_URL=domain3.com
      - HOST3_LOCATION=my-other-website
      - HOST3_SSL_EMAIL = email@domain1.com

      # Reverse proxy. Single url. With HTTP authentication. Without SSL certificate.
      - HOST4_URL=domain4.com
      - HOST4_LOCATION=10.0.0.14:2222
      - HOST4_AUTH=username1=password1
```
