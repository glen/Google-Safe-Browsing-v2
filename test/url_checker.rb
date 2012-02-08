require 'rubygems'
require 'uri'
require 'net/http'
require 'time'
require 'redis'
require 'digest'
require 'iconv'
require 'yaml'

# File used to read the domains, I am using Alexa's 1 million domains list
URL_FILE = "top-1m.csv"

CONFIG = YAML.load(File.read(File.expand_path(File.join('config', 'config.yml'))))["development"]
# We are putting the config.yml file into CONFIG and using it as CONFIG.key.
# This is all done using daemon-kit. 
# In lieu of daemon kit we would need to still access the methods similarly
# Hence the code below.
# Only for Ruby 1.9.2 for 1.8.7  use code further down
if RUBY_VERSION == "1.9.2"
  CONFIG.each do |key, value|
    CONFIG.define_singleton_method(key.to_sym){value}
  end
else
# For Ruby 1.8.7 use the following code
  CONFIG.each do |key, value|
    Hash.send(:define_method, key.to_sym, proc{value})
  end
end

%w{db_helper.rb url_helper.rb canonicalize_helper.rb string.rb}.each do |file|
  require File.expand_path(File.join('helpers', file))
end
require File.expand_path(File.join('lib', 'update_list.rb'))

all_urls = []

# Opening the Alexa 1 million domain file, read each entry and put into an array.
#File.open(URL_FILE) do |file|
# until file.eof?
#    line = file.readline
#    domain = line.split(',')[1].strip
#    all_urls << "http://#{domain}"
#  end
#end

# Else we can add the urlss that we need to check in the array as below
all_urls = ["http://gumblar.cn"]

puts "Starting @ #{Time.now}"
all_urls.each do |url|
  begin
    puts "@ #{Time.now} => #{url} is unsafe!" unless DbHelper.clean?(url)
  rescue Exception => e
    puts "Got Exception #{e} for #{url}"
  end
end
puts "Finished @ #{Time.now}"
