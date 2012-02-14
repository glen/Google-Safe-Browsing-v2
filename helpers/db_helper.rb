module DbHelper

  $DB_ADD = Redis.new(:db => CONFIG.add_db)
  $DB_SUB = Redis.new(:db => CONFIG.sub_db)
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
    
    hostkeys = []
    prefixes = []
    
    # Segregates the urls into hostkeys and prefixes
    urls_to_check.each{|url| hostkeys << url if url.match(/[^\/]*/)[0].count('.') == 1}
    prefixes = urls_to_check - hostkeys

    return [hostkeys, prefixes]
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

  def self.matched_prefixes(matches)
    prefixes = []
    matches.each do |match|
      prefixes << ($DB_ADD.smembers match)
    end
    prefixes.flatten.uniq
  end

  def self.clean?(query_url)
    url = Canonicalize.canonicalize(query_url)
#    url = query_url  
#    DaemonKit.logger.info "Cleaning url #{query_url} gives #{url}"
    digests = []
    prefixes = []

    hostkeys, prefixes = DbHelper.check_url(url)
 
    digest_hostkeys = DbHelper.digests(hostkeys)
    sliced_digest_hostkeys = DbHelper.sliced_digests(digest_hostkeys)

    if prefixes.empty?
      sliced_digest_prefixes = []
    else
      digest_prefixes = DbHelper.digests(prefixes)
      sliced_digest_prefixes = DbHelper.sliced_digests(digest_prefixes)
    end
    
    hostkey_matches = DbHelper.in_db?(sliced_digest_hostkeys, "add_host")
    
    prefix_matches = []
    # if hostkey found
    unless hostkey_matches.empty?
      # hostkey has a prefix
      unless sliced_digest_prefixes.empty?
        # if any one of the prefixes of the matched hostkeys matches with combinations
        prefix_matches = (matched_prefixes(hostkey_matches) & (sliced_digest_hostkeys + sliced_digest_prefixes).flatten.uniq)
        unless prefix_matches.empty?
          # Check Subs
          sub_matches = []
          sub_matches << DbHelper.in_db?(prefix_matches, "sub_host")
          sub_matches << DbHelper.in_db?(prefix_matches, "sub_prefix")
          sub_matches.flatten!
          sub_matches.uniq!
          # If not in subs then do full hash lookup
          unless sub_matches.empty?
#            puts "Performing lookup for #{url} prefix"
            full_hashes = query_for_full_hash(prefix_matches)
            full_hashes.each do |chunk, full_hash|
              full_hash.each do |hash|
                return false if (digest_hostkeys + digest_prefixes).flatten.uniq.include?(hash)
              end
            end
            return true         
          else
            return true
          end
        else
          return true
        end
      # hostkey does not have prefix, meaning whole domain is bad
      # hence check the subs with the hostkey_matches
      else
        # Check Subs
        sub_matches = []
        sub_matches = DbHelper.in_db?(hostkey_matches, "sub_host")
        # If not in subs then do full hash lookup
        if sub_matches.empty?
#          puts "Performing lookup for #{url} hostkey"
          full_hashes = query_for_full_hash(hostkey_matches)
          full_hashes.each do |chunk, full_hash|
            full_hash.each do |hash|
              return false if digest_hostkeys.include?(hash)
            end
          end
          return true         
        else
          return true
        end        
      end
    else
      return true
    end  
  end

  def self.has_path?(url)
    !["/", ""].include?(URI.parse(url).path)
  end
end
