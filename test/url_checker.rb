require 'rubygems'
require 'digest'
require 'redis'
require 'iconv'
require 'net/http'
require 'ruby-debug'
URL_FILE = "top-1m.csv"

class String
  def to_my_utf8
    ::Iconv.conv('UTF-8//IGNORE', 'UTF-8', self + ' ')[0..-2]
  end
end

module DbHelper

  def self.check_url(url)
    urls_to_check = []
    unless url == "/" or url.empty?
      u = url.strip
      u = u.gsub("\n", "")
      u = u.sub(/\/\Z/,"") while u.match(/\/\Z/) # Removes all trailing slashes; we need to have only one and we add it below
      stripped_url = u.strip.sub(/(https?:)?\/\//, "").sub(/:\d*/, '') + "/" # Removes 'http://' and adds a trailing slash
      urls_to_check << get_urls(stripped_url)
      return [urls_to_check.flatten.uniq, []] if numeric_host?(url)
      ary = stripped_url.split('/').first.split('.')
      last = stripped_url.split('/').slice(1,10).join('/') if stripped_url.split('/').length > 1
      ary = ary.slice(ary.length-6, 10) if ary.length > 6
      while ary.length > 2
        ary = ary.slice(1,5)
        unless last.nil?
          urls_to_check << get_urls(ary.join('.') + "/" + last)
        else
          urls_to_check << get_urls(ary.join('.') + "/")
        end
      end
    end
    urls_to_check.flatten!
    urls_to_check.uniq!
    hosts = []
    urls = []
    urls_to_check.each{|url| hosts << url if UrlHelper.host(url) == url }
    urls = urls_to_check - hosts
    return [hosts, urls]
  end

  def self.get_urls(u)
    urls = []
    stripped_url = u.strip.sub("http://", "").sub(/:\d*/, '')
    urls << stripped_url
    urls << stripped_url.split('?').first if stripped_url.match(/\?/)
    urls << stripped_url.split('/').first  + "/" if stripped_url.match(/\//)

    ary = []
    ary = stripped_url.split('?').first.split('/')
    ary.pop
    urls << ary.join('/') + "/" unless ary.empty?
    
    a = []
    urls.uniq.each{|url| a << url }
    return a
  end

  def self.numeric_domain(url)
    domain_regex = %r{https?:\/\/(.+?)\/}
    domain = domain_regex.match(url)[1]
    "#{domain}/"
  end


  def self.numeric_host?(url)
    if url =~ /https?:\/\/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
      return true
    else
      return false
    end
  end

  def self.digests(urls)
    sha256 = []
    urls.each do |url|
      sha256 << Digest::SHA256.digest(url)#.slice(0,4)
    end
    sha256
  end

  def self.in_db?(digests, set)
    return [] if digests.empty?
    db = set.match(/\Aadd/)? $DB_ADD : $DB_SUB  
    matches = []
    digests.each do |digest|
      if db.sismember set, digest
        matches << digest
      end
    end
    return matches
  end

  def self.sliced_digests(digests)
    sliced_digests = []
    digests.each do |digest|
      sliced_digests << digest.slice(0,4)
    end
    sliced_digests
  end

  def self.get_full_hash(data)
    full_hashes = {}
    while data.length > 0
      meta_data = data.match(/\Agoog.*-shavar:(\d*):(\d*)\n/)
      if meta_data
        add_chunk = meta_data[1]
        full_hash_length = meta_data[2].to_i
        hashes = []
        data = data.sub("#{meta_data}", "")
        full_hash = data.slice(0, full_hash_length)
        hashes << full_hash
        data = data.sub(full_hash, "")
        if full_hashes.keys.include?(add_chunk)
          hashes = full_hashes[add_chunk]
          hashes << full_hash
          hashes.flatten!
        end
        full_hashes.merge!(add_chunk => hashes)
      end
    end
    full_hashes
  end

  def self.query_for_full_hash(prefixes)
    all_prefixes = prefixes.join
    each_prefix_length = 4
    prefixes_length = each_prefix_length * prefixes.length
    req_for_full_hash = "/safebrowsing/gethash?"
    uri = URI.parse("http://safebrowsing.clients.google.com:80")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new("#{req_for_full_hash}client=api&apikey=ABQIAAAA-t1csGopkAhNhvTQ77r9ZBQP0vwtqyMLtc_mqF3ciVtXzabIaA&appver=0.0.1&pver=2.2")
    request.body = "#{each_prefix_length}:#{prefixes_length}\n#{all_prefixes}"
    response = http.request(request)
    full_hashes = {}
    if response.code == "200"
      full_hashes = get_full_hash(response.body)
    elsif response.code == "204"
      return {}
    end
    full_hashes
  end

  def self.clean?(query_url)
    url = Canonicalize.canonicalize(query_url)
    digests = []
    prefixes = []
    blacklist_digests = []
    whitelist_digests = []
    hosts, urls = check_url(url)
  
    digest_hosts = digests(hosts)
    sliced_digest_hosts = sliced_digests(digest_hosts)
    blacklist_digests = in_db?(sliced_digest_hosts, "add_host")
    whitelist_digests = in_db?(blacklist_digests, "sub_host") unless blacklist_digests.empty?
    digests = blacklist_digests - whitelist_digests
    puts "#{url}" unless whitelist_digests.empty? 

    unless digests.empty?
      full_hashes = query_for_full_hash(digests)
      full_hashes.each do |chunk, full_hash|
        full_hash.each do |hash|
          if digest_hosts.include?(hash)
            return false
          end
        end
      end
    end

    digest_prefixes = digests(urls)
    sliced_digest_prefixes = sliced_digests(digest_prefixes)

    blacklist_prefixes = in_db?(sliced_digest_prefixes, "add_prefix")
    whitelist_prefixes = in_db?(blacklist_prefixes, "sub_prefix")

    prefixes = blacklist_prefixes - whitelist_prefixes

    unless prefixes.empty?
      full_hashes = query_for_full_hash(prefixes)
      full_hashes.each do |chunk, full_hash|
        full_hash.each do |hash|
          if digest_prefixes.include?(hash)
            return false
          end
        end
      end
    end

    return true
  end

  def self.has_path?(url)
    !["/", ""].include?(URI.parse(url).path)
  end
end

module UrlHelper

  def self.malformed_url?(url)
    url.match(/(.*):\/\/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\d{1,10}|[^\/]*)(\/.*)*/).nil?
  end

  def self.host(url)
    url.match(/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\d{1,10}|[^\/]*)(\/.*)*/)[0]
  end

end

module Canonicalize

  def self.canonicalize(url)
#    input = url.encode('UTF-8')
    input = url.to_my_utf8
    input = input.strip
    input = input.gsub(/\\r|\\t|\\n/, '')
    input = "http://#{input}" if input.match(/\Awww/)
    input = "http:#{input}" if input.match(/\A\//)
    input = "http://#{input}" if input.match(/\A\/\//)
    input = "http://#{input}" unless input.match(/\Ahttp|www/)

    input = input.gsub(/ /, '%20')

    url = input.match(/(.*):\/\/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\d{1,10}|[^\/]*)(\/.*)*/)

    scheme = url[1]
    domain = url[2]
    domain = domain.gsub(/\.{2,}/, '')
    domain = hex_encode(domain, "domain")
    domain = [domain.to_i].pack("N*").unpack("C4").join('.') if domain.match(/\A\d{1,10}\z/)

    path   = url[3].nil? ? "/" : url[3]
    path   = path.sub(/#.*/, '')
    path   = path.sub(/\A\//, '') if path.match(/\A\/\//)
    path   = File.expand_path(path) if path.match(/\.{1,2}/)
    path   = hex_encode(path, "path")

    clean_url = "#{scheme}://#{domain}#{path}"

    clean_url = clean_url.gsub(/\\x/, '%')
    if input.match(/\/\z/) && !path.match(/.*\/\z/)
      clean_url = "#{clean_url}/"
    end
    clean_url
  end

  def self.recursive_percent_escape(url)
    if url.match(/%[0-7][a-f,A-F,0-9]/)
      percent_hex = url.match(/%[a-f,A-F,0-9]{2}/).to_s
      url = url.sub(percent_hex, percent_hex.sub('%','').hex.chr)
      recursive_percent_escape(url)
    else
      return url
    end
  end

  def self.special_percent_escape(url)
    new_url = []
    url = "#{url}25" if url.match(/%\z/)
    url = url.gsub('%%','%25%')
    url.split('%').each_with_index do |part, index|
     	if index == 0
		    new_url << part
		    next
	    end
	    if part.strip.empty?
		    new_url << "25"
		    next
	    end
	    part.match(/\A[0-9,a-f,A-f][a-f,A-F,0-9]/) ? new_url << part : new_url << "25#{part}"
    end
    url = new_url.join('%')
    return url
  end

  def self.percent_escaped_upcase(url)
    begin
      percent_escaped = url.match(/%([0-9][a-f]|[a-f]{2}|[a-f][0-9])/)
      url = url.sub(percent_escaped.to_s, percent_escaped.to_s.upcase)
    end until percent_escaped.nil?
    url
  end

  def self.hex_encode(str, type)
    clean_url = ""
    # used in Ruby 1.9
#    recursive_percent_escape(str.strip).encode('UTF-8').bytes{|byte|
    # no encode in 1.8.7 hence overwrote that - prefereable way is encode
    recursive_percent_escape(str.strip).to_my_utf8.bytes{|byte| 
      if byte <= 32 || byte >= 127 || byte == 35 || byte == 37
			  byte.chr == "%" ? clean_url << byte.chr : clean_url << "%#{byte.to_s(16).upcase}"
      else
        if type == "domain"
          clean_url << byte.chr.downcase
        else
          clean_url << byte.chr
        end
      end
    }
    percent_escaped_upcase(clean_url)
  end

end

$DB_ADD = Redis.new(:db => 10)
$DB_SUB = Redis.new(:db => 11)
debugger
all_urls = []
File.open(URL_FILE) do |file|
 until file.eof?
    line = file.readline
    domain = line.split(',')[1].strip
    all_urls << "http://#{domain}"
  end
end

puts "Starting @ #{Time.now}"
all_urls.each do |url|
  begin
    puts "@ #{Time.now} => #{url} is unsafe!" unless DbHelper.clean?(url)
  rescue Exception => e
    puts "Got Exception #{e} for #{url}"
  end
end
puts "Finished @ #{Time.now}"
