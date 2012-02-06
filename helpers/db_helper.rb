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
#    urls_to_check.each{|url| hosts << url if URI.parse("http://#{url}").host + "/"  == url}
    urls_to_check.each{|url| hosts << url if UrlHelper.host(url) == url}
    urls = urls_to_check - hosts
#    DaemonKit.logger.info "for url #{url} => hosts are #{hosts.join(', ')}|urls are #{urls.join(', ')}"

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
    db_type = set.match(/\Aadd/)? 10 : 11
    db = Redis.new(CONFIG.database_configuration.merge(:db => db_type))
    matches = []
    digests.each do |digest|
      if db.sismember set, digest
        matches << digest
      end
    end
    db.quit
    return matches
  end

  def self.sliced_digests(digests)
    sliced_digests = []
    digests.each do |digest|
      sliced_digests << digest.slice(0,4)
    end
    sliced_digests
  end

  def self.clean?(query_url)
    url = Canonicalize.canonicalize(query_url)
#    url = query_url  
    DaemonKit.logger.info "Cleaning url #{query_url} gives #{url}"
    digests = []
    prefixes = []

    hosts, urls = check_url(url)
  
    digest_hosts = digests(hosts)
    puts digest_hosts
    sliced_digest_hosts = sliced_digests(digest_hosts)
    blacklist_digests = in_db?(sliced_digest_hosts, "add_host")
    whitelist_digests = in_db?(blacklist_digests, "sub_host")
    digests = blacklist_digests - whitelist_digests
    
    unless digests.empty?
      DaemonKit.logger.info "Performing lookup for #{url}"
      full_hashes = query_for_full_hash(digests)
      full_hashes.each do |chunk, full_hash|
        full_hash.each do |hash|
          if digest_hosts.include?(hash)
            DaemonKit.logger.info "Got full hash match of host for #{url} in chunk #{chunk}"
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
      DaemonKit.logger.info "Performing lookup for #{url} for prefix"
      full_hashes = query_for_full_hash(prefixes)
      full_hashes.each do |chunk, full_hash|
        full_hash.each do |hash|
          if digest_prefixes.include?(hash)
            DaemonKit.logger.info "Got full hash match of prefix for #{url} in chunk #{chunk}"
            return false
          end
        end
      end
    end

    DaemonKit.logger.info "Clean for #{url}"
    return true
  end

  def self.has_path?(url)
    !["/", ""].include?(URI.parse(url).path)
  end
end