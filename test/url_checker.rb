require 'rubygems'
require 'ruby-debug'
require 'uri'
require 'net/http'
require 'time'
require 'redis'
require 'digest'
require 'iconv'

CONFIG = YAML.load(File.read(File.expand_path(File.join('config', 'config.yml'))))["development"]

class Hash
  def method_missing(method_name, *args, &block)
    self[method_name.to_s]
  end
end

%w{db_helper.rb url_helper.rb canonicalize_helper.rb string.rb}.each do |file|
  require File.expand_path(File.join('helpers', file))
end
require File.expand_path(File.join('lib', 'update_list.rb'))

URL_FILE = "top-1m.csv"

all_urls = ["http://gumblar.cn"]
#File.open(URL_FILE) do |file|
# until file.eof?
#    line = file.readline
#    domain = line.split(',')[1].strip
#    all_urls << "http://#{domain}"
#  end
#end

puts "Starting @ #{Time.now}"
all_urls.each do |url|
  begin
    puts "@ #{Time.now} => #{url} is unsafe!" unless DbHelper.clean?(url)
  rescue Exception => e
    puts "Got Exception #{e} for #{url}"
  end
end
puts "Finished @ #{Time.now}"
