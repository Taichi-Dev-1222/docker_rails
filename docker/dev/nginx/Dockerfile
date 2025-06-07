FROM nginx:latest

RUN rm -f /etc/nginx/conf.d/default.conf

COPY docker/dev/nginx/conf/dev-rails.techbull.cloud.conf /etc/nginx/conf.d/dev-rails.techbull.cloud.conf
COPY docker/dev/nginx/conf/nginx.conf /etc/nginx/nginx.conf

COPY certs/dev-rails.techbull.cloud.pem /etc/nginx/ssl/dev-rails.techbull.cloud.pem
COPY certs/dev-rails.techbull.cloud-key.pem /etc/nginx/ssl/dev-rails.techbull.cloud-key.pem

#リッスンポートの指定
EXPOSE 80 443

CMD /usr/sbin/nginx -g 'daemon off;' -c /etc/nginx/nginx.conf