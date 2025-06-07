
docker_rails配下にrailsのソースをダウンロード
rails new docker_rails --database=mysql

各コンテナを作成するためのイメージをDockerfileからビルド
- Nginx
まずDockerfile
```
FROM nginx:latest

RUN rm -f /etc/nginx/conf.d/default.conf

COPY docker/dev/nginx/conf/dev-rails.techbull.cloud.conf /etc/nginx/conf.d/dev-rails.techbull.cloud.conf
COPY docker/dev/nginx/conf/nginx.conf /etc/nginx/nginx.conf

COPY certs/dev-rails.techbull.cloud.pem /etc/nginx/ssl/dev-rails.techbull.cloud.pem
COPY certs/dev-rails.techbull.cloud-key.pem /etc/nginx/ssl/dev-rails.techbull.cloud-key.pem

#リッスンポートの指定
EXPOSE 80 443

#コンテナ起動時にNginxをフォアグラウンドで起動する
#-g 'daemon off;' はDockerで必要（デーモン化するとコンテナが終了してしまうため）。
#-c で読み込む設定ファイルを明示（通常は省略可だが、カスタムパスのときは必須）。
CMD /usr/sbin/nginx -g 'daemon off;' -c /etc/nginx/nginx.conf
```

- 解説
COPYのコピー元のパスはDockerfileのビルドコンテキストからの相対パスとして解釈される
→docker-compose.ymlで以下のようにビルドコンテキストを指定している
```
  nginx:
    build:
      context: ../../
      dockerfile: docker/dev/nginx/Dockerfile
```

- Virtual Host "dev-rails.techbull.cloud.conf"
```
upstream app {
    server unix:/var/www/app/tmp/sockets/puma.sock;
}

server {
    listen 80;
    server_name dev-rails.techbull.cloud;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name dev-rails.techbull.cloud;

    ssl_certificate     /etc/nginx/ssl/dev-rails.techbull.cloud.pem;
    ssl_certificate_key /etc/nginx/ssl/dev-rails.techbull.cloud-key.pem;

    root /var/www/app/public;
    index index.html;

    access_log /var/log/nginx/dev-rails.techbull.cloud.access.log;
    error_log  /var/log/nginx/dev-rails.techbull.cloud.error.log;

    location / {
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Client-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60;
        proxy_read_timeout    60;
        proxy_send_timeout    60;
        send_timeout          60;

        proxy_pass http://app;

        try_files $uri @app;
    }

    location @app {
        proxy_pass http://app;
    }

    client_max_body_size 100m;

    error_page 404             /404.html;
    error_page 500 502 503 504 /500.html;

    keepalive_timeout 5;
}
```

細かく区切って解説
https://zenn.dev/na0kia/articles/c68cfd65dcbdda
```
upstream app {
    server unix:/var/www/app/tmp/sockets/puma.sock;
}
```
Nginx → Puma への通信経路（UNIXソケット）を app という名前で定義する
upstreamはリバースプロキシ先のバックエンドのサーバのグループ定義
ここで定義したappはNginx設定内で再利用可能
PumaがUNIXドメインソケット経由でリクエストを受ける設定
🧠 UNIXソケットのメリット：
	•	Dockerコンテナ内ではループバック通信より速い
	•	TCPポートを使わないのでセキュリティ的にも良い
🧠 パス /var/www/app/tmp/sockets/puma.sock の根拠：
Rails/Puma で、config/dev_puma-socket.rb内で以下のようにPuma起動時にソケットを作成するように指定
```
bind 'unix:///var/www/app/tmp/sockets/puma.sock'
```

```
try_files $uri @app;
```
try_filesディレクティブは静的なコンテンツと動的なコンテンツを振り分けたり、
存在しないファイルを指定された場合にホームページに飛ばしたりといったことができる。
最初の引数で指定されたファイルを探していき、見つからなければ次の引数に移行します。
そして最初に見つかったファイルをクライアントのリクエストの処理に用います。
ファイルがみつからなかった場合は最後の引数に指定したURIかステータスコードを返します


```
location / {
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Client-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60;
        proxy_read_timeout    60;
        proxy_send_timeout    60;
        send_timeout          60;

        proxy_pass http://app;

        try_files $uri @app;
    }
```
Hostヘッダーは、リクエストが送信される先のサーバーのホスト名とポート番号を指定します。
ポート番号は省略可能です。そして、$http_hostはHTTPリクエストのHostヘッダーの値です
X-Real-IPヘッダーに$remote_addrを用いて、クライアントのIPを指定しています
proxy_set_headerはバックエンドにアクセスする時のリクエストにヘッダを付与します
proxy_set_header X-Forwarded-For $remote_addr;のようにクライアントのIPをそのままXFFのヘッダに割り当てることができる


```
    location @app {
        proxy_pass http://app;
    }
```
proxy_passディレクティブはリバースプロキシの設定を行うディレクティブです
ここではupstreamで指定されたAPサーバーのパスを指定しています

- app/rubyコンテナ
Dockerfile
```
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
```
gem（ジェム）とは、Ruby のプログラムを部品（ライブラリ）としてまとめたもの
gemの例
rails: Webアプリのフレームワーク
devise: ログイン昨日などのユーザ認証
mysql2: MySQLとの接続ドライバ
puma: アプリを実行するWebサーバ

🎯 gem ⇔ Bundler の関係
gem = 部品（個々のライブラリ）
Bundler = 部品をまとめて管理する道具

bundle install は、Ruby プロジェクトで指定された gem（ライブラリ）を一括でインストールするコマンド
Gemfileに記載のgem (gem名)を調べてバージョンも含めて全てインストールする
📦 動作の流れ
	1.	Gemfile を読み込む
	2.	必要な gem を特定する
	3.	Gemfile.lock を作成 or 更新する（依存バージョンが確定する）
	4.	gem をローカルにインストールする

```
CMD ["bundle", "exec", "puma", "-C", "config/dev_puma-socket.rb", "-e", "development"]
```
→これは「Puma を Rails 環境 development で、設定ファイルを読み込んで起動しなさい」という意味
bundle：Bundlerのコマンド。Rubyのgem(ライブラリ)をただ串区管理・実行するためのツール。
exec: Bundler経由でgemのコマンドを実行する指示。
puma: Rails用のAPPサーバ
-C config/dev_puma-socket.rb: Pumaの設定ファイルを指定。中のbindでソケットを作成している。
-e development: Rails環境をdevelopmentモードで起動するという指定。

development.rb内の以下は、Railsのホスト名チェック（Host Authorization）機能に、許可するホスト名を追加する設定
🔍 背景：config.hosts とは？
Rails 6 以降では、ホストヘッダインジェクション攻撃を防ぐために、受け入れるホスト名を制限する仕組み（Host Authorization）が導入されました。
```
#Dockerなどで nginx → app にプロキシされる場合、内部ネットワークで Host: app が使われるケースがあり、それを許可。
config.hosts << "app"
#ブラウザで https://dev-rails.techbull.cloud にアクセスすると Host: dev-rails.techbull.cloud が送信される
config.hosts << "dev-rails.techbull.cloud"
```

database.yml
Rails アプリが MySQL と接続するための設定ファイル
defaultsセクション
```
default: &default
  adapter: mysql2
  encoding: utf8mb4
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  username: root
  password: <%= ENV["MYSQL_ROOT_PASSWORD"] %>
  host: db
  port: <%= ENV.fetch("MYSQL_PORT") { 3306 } %>
```
共通設定を定義して、各環境で使い回すためのベースです。
•	adapter: mysql2
→使用するDBアダプタ（MySQL用）
•	encoding: utf8mb4
→絵文字なども扱えるUTF-8の拡張版
•	pool:
→DB接続の最大スレッド数（環境変数 or 5）
•	username: root
→MySQLに接続するユーザー名（例：root）
•	password:
→環境変数 MYSQL_ROOT_PASSWORD から取得
•	host: db
→MySQLホスト名（Docker環境なら db はサービス名）
•	port:
→MySQLポート（環境変数 or デフォルト3306）



- MySQL
Dockerfile
```
FROM mysql:8.0

ENV TZ Asia/Tokyo
ENV LC_ALL ja_JP.UTF-8

#最初に含まれる MySQL の apt ソースを一時的に無効化して、apt-get update が失敗しないようにする
RUN mv /etc/apt/sources.list.d/mysql.list /etc/apt/sources.list.d/mysql.list.disabled

#curl をインストール。後続の GPG キー取得に必要
RUN apt-get update \
 && apt-get install -y \
       curl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

#MySQL リポジトリの GPG鍵を手動で取得し、登録
RUN curl -sSfL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 | gpg --import
RUN gpg --batch --export "B7B3B788A8D3785C" > /etc/apt/keyrings/mysql.gpg

#一時的に無効化していた MySQL ソースを再度有効化
RUN mv /etc/apt/sources.list.d/mysql.list.disabled /etc/apt/sources.list.d/mysql.list

#最新のパッケージリストを再取得
RUN apt-get update

<!-- locales：ロケール設定に必要
python：一部管理用スクリプトなどに必要になることがある
vim：任意、手動デバッグ時に便利
clean と rm -rf でキャッシュを削除（軽量化） -->
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

RUN mkdir /var/mysql \
    && chown mysql:adm /var/mysql \
    && rm -rf /etc/mysql/conf.d

COPY docker/dev/mysql/my.cnf /etc/mysql/

#secure-file-priv で指定されるディレクトリが存在しないと 起動エラー になるので事前に作成＆権限付与
RUN mkdir -p /var/lib/mysql-files && \
    chown -R mysql:mysql /var/lib/mysql-files
```



docker-compose.yml
```
version: '3.8'

services:
  app:
    build:
      context: ../../
      dockerfile: docker/dev/app/Dockerfile
    container_name: app_ruby
    env_file:
      - ../../.env
    volumes:
      - ../../:/var/www/app
      - puma_socket:/var/www/app/tmp/sockets
    depends_on:
      - db
      - redis

  db:
    build:
      context: ../../
      dockerfile: docker/dev/mysql/Dockerfile
    container_name: db_mysql
    env_file:
      - ../../.env
    ports:
      - "3306:3306"
    volumes:
      - ./mysql/db_data:/var/lib/mysql
      

  redis:
    image: redis:latest
    container_name: redis
    ports:
      - "6379:6379"
    volumes:
      - ./redis/db_data:/data

  nginx:
    build:
      context: ../../
      dockerfile: docker/dev/nginx/Dockerfile
    container_name: dev_nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ../../:/var/www/app
      - puma_socket:/var/www/app/tmp/sockets
    depends_on:
      - app

volumes:
  puma_socket:
```







DBマイグレーション確認
```
iwakitaichi@Mac dev % docker-compose exec app bundle exec rails generate migration CreateUsers name:string email:string
WARN[0000] /Users/iwakitaichi/git/menta/docker_rails/docker/dev/docker-compose.yml: the attribute `version` is obsolete, it will be ignored, please remove it to avoid potential confusion
      invoke  active_record
      create    db/migrate/20250526111024_create_users.rb
iwakitaichi@Mac dev %
iwakitaichi@Mac dev %
iwakitaichi@Mac dev % docker-compose exec app bundle exec rails db:migrate
WARN[0000] /Users/iwakitaichi/git/menta/docker_rails/docker/dev/docker-compose.yml: the attribute `version` is obsolete, it will be ignored, please remove it to avoid potential confusion
== 20250526111024 CreateUsers: migrating ======================================
-- create_table(:users)
   -> 0.0370s
== 20250526111024 CreateUsers: migrated (0.0371s) =============================

iwakitaichi@Mac dev %
iwakitaichi@Mac dev % docker-compose exec app bundle exec rails db:migrate:status
WARN[0000] /Users/iwakitaichi/git/menta/docker_rails/docker/dev/docker-compose.yml: the attribute `version` is obsolete, it will be ignored, please remove it to avoid potential confusion

database: techbull-rails

 Status   Migration ID    Migration Name
--------------------------------------------------
   up     20250526111024  Create users

iwakitaichi@Mac dev %
```