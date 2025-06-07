# config/dev_puma-socket.rb
directory '/var/www/app'

rackup '/var/www/app/config.ru'

bind 'unix:///var/www/app/tmp/sockets/puma.sock'

environment ENV.fetch('RAILS_ENV') { 'development' }

pidfile '/var/www/app/tmp/pids/puma.pid'
state_path '/var/www/app/tmp/pids/puma.state'
stdout_redirect '/var/www/app/log/puma.stdout.log', '/var/www/app/log/puma.stderr.log', true

workers 1
threads 1, 6

preload_app!

plugin :tmp_restart