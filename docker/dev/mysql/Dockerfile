FROM mysql:8.0

ENV TZ Asia/Tokyo
ENV LC_ALL ja_JP.UTF-8

RUN mv /etc/apt/sources.list.d/mysql.list /etc/apt/sources.list.d/mysql.list.disabled

RUN apt-get update \
 && apt-get install -y \
       curl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN curl -sSfL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 | gpg --import
RUN gpg --batch --export "B7B3B788A8D3785C" > /etc/apt/keyrings/mysql.gpg
RUN mv /etc/apt/sources.list.d/mysql.list.disabled /etc/apt/sources.list.d/mysql.list
RUN apt-get update

RUN apt-get install -y --no-install-recommends\
    locales \
    python \
    vim \
    && apt-get clean \
    && rm -rf /var/cache/apt/archives/* \
    /var/lib/apt/lists/*

RUN echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen ja_JP.UTF-8

# Setup MySQL
RUN touch /var/log/mysqld.log \
    && chown mysql:adm /var/log/mysqld.log

COPY docker/dev/mysql/my.cnf /etc/mysql/

RUN mkdir -p /var/lib/mysql-files && \
    chown -R mysql:mysql /var/lib/mysql-files