FROM php:8.0.9-fpm-alpine

LABEL maintainer="Patrick McCarren <patrick@wedgehr.com>"

ENV php_conf /usr/local/etc/php-fpm.conf
ENV fpm_conf /usr/local/etc/php-fpm.d/www.conf
ENV php_vars /usr/local/etc/php/conf.d/docker-vars.ini

ENV CADDY_VERSION 2.4.3

# resolves #166
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php
RUN apk add --no-cache --repository http://dl-3.alpinelinux.org/alpine/edge/community gnu-libiconv

RUN addgroup -S nginx \
  && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \ 
  && apk add --no-cache --virtual \
    .build-deps \
    curl \
  \
  # forward request and error logs to docker log collector
  && mkdir -p /var/log/nginx && chown -R nginx:nginx /var/log/nginx \
  && ln -sf /dev/stdout /var/log/nginx/access.log \
  && ln -sf /dev/stderr /var/log/nginx/error.log

# note: json extension is installed in php 8.0 by default, so no need to add
RUN echo @testing http://nl.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories \
    && echo /etc/apk/respositories \
    && apk update && apk upgrade \
    && apk add --no-cache \
    wget \
    supervisor \
    curl \
    libcurl \
    git \
    make \
    gcc \
    autoconf \
    bash \
    gnupg \
    zlib-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    gd-dev \
    freetype-dev \
    freetype \
    postgresql-dev \
    libxslt-dev \
    musl-dev \
    libzip-dev \
    && docker-php-ext-configure gd \
      --with-freetype \
      --with-jpeg \
    && docker-php-ext-install \
        iconv \
        pgsql \
        pdo_pgsql \
        gd \
        exif \
        intl \
        xsl \
        soap \
        dom \
        zip \
        opcache \
    && pecl install -o -f redis \
    && echo "extension=redis.so" > /usr/local/etc/php/conf.d/redis.ini \
    && docker-php-source delete \
    && mkdir -p /etc/nginx \
    && mkdir -p /var/www/app \
    && mkdir -p /run/nginx \
    && mkdir -p /var/log/supervisor \
    && php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php composer-setup.php --quiet --install-dir=/usr/bin --filename=composer \
    && rm composer-setup.php \
    && apk del .build-deps musl-dev linux-headers libffi-dev make autoconf gcc


COPY conf/supervisord.conf /etc/supervisord.conf

# Copy our nginx config
RUN rm -Rf /etc/nginx/nginx.conf
COPY conf/nginx.conf /etc/nginx/nginx.conf

# nginx site conf
RUN mkdir -p /etc/nginx/sites-available/ && \
mkdir -p /etc/nginx/sites-enabled/ && \
rm -Rf /var/www/* && \
mkdir /var/www/html/
COPY conf/nginx-site.conf /etc/nginx/sites-available/default.conf
# ssl site disabled for now
#COPY conf/nginx-site-ssl.conf /etc/nginx/sites-available/default-ssl.conf
RUN ln -s /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf

# tweak php-fpm config
RUN echo "cgi.fix_pathinfo=0" > ${php_vars} &&\
    echo "upload_max_filesize = 100M"  >> ${php_vars} &&\
    echo "post_max_size = 100M"  >> ${php_vars} &&\
    echo "variables_order = \"EGPCS\""  >> ${php_vars} && \
    echo "memory_limit = 128M"  >> ${php_vars} && \
    sed -i \
        -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" \
        -e "s/pm.max_children = 5/pm.max_children = 4/g" \
        -e "s/pm.start_servers = 2/pm.start_servers = 3/g" \
        -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" \
        -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" \
        -e "s/;pm.max_requests = 500/pm.max_requests = 200/g" \
        -e "s/user = www-data/user = nginx/g" \
        -e "s/group = www-data/group = nginx/g" \
        -e "s/;listen.mode = 0660/listen.mode = 0666/g" \
        -e "s/;listen.owner = www-data/listen.owner = nginx/g" \
        -e "s/;listen.group = www-data/listen.group = nginx/g" \
        -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" \
        -e "s/^;clear_env = no$/clear_env = no/" \
        ${fpm_conf}
#    ln -s /etc/php7/php.ini /etc/php7/conf.d/php.ini && \
#    find /etc/php7/conf.d/ -name "*.ini" -exec sed -i -re 's/^(\s*)#(.*)/\1;\2/g' {} \;


# copy in code
COPY src/ /var/www/html/
COPY errors/ /var/www/errors
COPY scripts/ /scripts

EXPOSE 80

WORKDIR "/var/www/html"
CMD ["/start.sh"]
