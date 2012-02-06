# If you need to 'vendor your gems' for deploying your daemons, bundler is a
# great option. Update this Gemfile with any additional dependencies and run
# 'bundle install' to get them all installed. Daemon-kit's capistrano
# deployment will ensure that the bundle required by your daemon is properly
# installed.

source :gemcutter

# daemon-kit
gem 'daemon-kit'
gem 'capistrano'
gem 'capistrano-ext'
gem 'eventmachine'
gem 'eventmachine_httpserver'
gem 'redis'
gem 'json'
gem 'domainatrix'
#gem 'iconv'

if RUBY_VERSION.match(/1\.9\.2/)
  gem 'ruby-debug19'
else
  gem 'ruby-debug'
end

# For more information on bundler, please visit http://gembundler.com
