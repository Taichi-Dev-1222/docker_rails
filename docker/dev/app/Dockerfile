FROM ruby:3.4.1
ENV APP_ROOT /var/www/app
ENV PATH="/usr/local/bundle/bin:$PATH"

RUN mkdir -p /var/www/app
WORKDIR $APP_ROOT

RUN mkdir -p /app/tmp/sockets

# 必要なパッケージのインストール前にcurlを用意
RUN apt-get update -y && \
    apt-get install -y curl gnupg && \
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian stable main" > /etc/apt/sources.list.d/yarn.list && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -


# OSパッケージとnode/yarn
RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    locales \
    vim \
    nodejs \
    redis-tools \
    yarn \
    mariadb-client && \
    rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*

    # Nodeバージョンアップ（例：23.4.0）と yarn install 準備
RUN npm install -g n && \
    n 24.0.2

# ロケール設定（UTF-8）
RUN localedef -f UTF-8 -i en_US en_US.UTF-8

# タイムゾーンを日本時間 (JST)
RUN cp -p /usr/share/zoneinfo/Japan /etc/localtime

# Bundlerインストール（バージョン固定）
RUN gem install bundler -v 2.5.23

RUN gem install rails -v 7.1.3

COPY Gemfile Gemfile.lock /var/www/app

RUN bundle install

# アプリケーション全体コピー（最後に）
COPY . $APP_ROOT

# yarn install はこの時点でできる（必要なら）
RUN if [ -f package.json ]; then yarn install; fi

# ポート開放（開発時）
EXPOSE 80

# PumaをUNIXソケット経由で起動
CMD ["bundle", "exec", "puma", "-C", "config/dev_puma-socket.rb", "-e", "development"]