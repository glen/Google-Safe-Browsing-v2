require 'eventmachine'
require 'evma_httpserver'
require 'uri'
require 'net/http'
require 'time'
require 'redis'
require 'json'
require 'domainatrix'
require 'digest'
require 'ruby-debug'
require 'iconv'

CONFIG = DaemonKit::Config.load("config.yml")

excluded_files = []
["gsb.rb"].each{|file| excluded_files << Dir.glob(File.join(DaemonKit.root, 'lib', file))}
(Dir.glob(File.join(DaemonKit.root, "lib", "*.rb")) - excluded_files.flatten).each{|f| require f}

Dir.glob(File.join(DaemonKit.root, "helpers", "*.rb")).each{|f| require f}


class String
  def to_my_utf8
    ::Iconv.conv('UTF-8//IGNORE', 'UTF-8', self + ' ')[0..-2]
  end
end

$DB_ADD = Redis.new(:db => 10)
$DB_SUB = Redis.new(:db => 11)

#debugger
puts "Uncomment the debugger above this line"
