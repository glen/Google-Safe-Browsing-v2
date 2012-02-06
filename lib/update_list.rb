def get_head_data(string)
  string.match(/(s|a):(\d*):(\d*):(\d*)\n/)
end


def get_add_data(data, hashlen)
  host_key_prefix = {}
  while data.length > 0
    hostkey = data.slice(0, 4)
    count_string = data.slice(4, 1)
    count = count_string.unpack("C")[0].to_i
    bytes_to_read = count * hashlen

    prefix_chunk = data.slice(5, bytes_to_read)
    prefixes = []

    prefix_string = prefix_chunk

    count.times do
      prefix = prefix_string.slice(0, hashlen)
      prefixes << prefix
      prefix_string = prefix_string.sub(prefix, "")
    end
    if host_key_prefix.keys.include?(hostkey)
      existing_hostkey_prefixes = host_key_prefix[hostkey]
      existing_hostkey_prefixes << prefixes
      prefixes = existing_hostkey_prefixes.flatten.uniq
      DaemonKit.logger.info "Merging for #{hostkey} prefixes now are #{prefixes.join(', ')}"
    end

    host_key_prefix.merge!({hostkey => prefixes})
    data = data.sub("#{hostkey}#{count_string}#{prefix_chunk}", "")
  end
  host_key_prefix
end


def get_sub_data(data, hashlen)
  host_key_prefix = {}
  while data.length > 0
    hostkey = data.slice(0, 4)
    count_string = data.slice(4, 1)
    count = count_string.unpack("C")[0].to_i
    add_chunk_num_prefix_pairs = []
    add_chunk_num = nil
    prefix_chunk = nil
    if count == 0
      prefix_chunk = data.slice(5, 4)
      add_chunk_num = prefix_chunk
      add_chunk_num_prefix_pairs << {add_chunk_num.unpack("N")[0] => nil}
    else
      bytes_to_read = count * (4 + hashlen)
      prefix_chunk = data.slice(5, bytes_to_read)
      prefix_string = prefix_chunk
      count.times do
        add_chunk_num = prefix_string.slice(0, 4)
        prefix = prefix_string.slice(4, hashlen)
#        add_chunk_num_prefix_pairs << {add_chunk_num.unpack("N")[0] => prefix.unpack("H*")[0]}
        add_chunk_num_prefix_pairs << {add_chunk_num.unpack("N")[0] => prefix}
        prefix_string = prefix_string.sub("#{add_chunk_num}#{prefix}", "")
      end
    end
#    host_key_prefix.merge!({hostkey.unpack("H*")[0] => add_chunk_num_prefix_pairs})
    host_key_prefix.merge!({hostkey => add_chunk_num_prefix_pairs})
    data = data.sub("#{hostkey}#{count_string}#{prefix_chunk}", "")
  end
  host_key_prefix
end

def get_full_hash(data)
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

def get_chunknum_query(nos)
  return "" if nos.empty?
  chunks = []
  array_length = nos.length
  if array_length - 1 == nos[array_length - 1].to_i - nos[0].to_i
    chunks << "#{nos[0]}-#{nos[array_length - 1]}"
    return chunks[0]
  end
  i = 0
  start = nos[i].to_i
  prev = nil
  loop do
    i += 1
    if i == nos.length
      if prev
        chunks << "#{start}-#{prev}"
      else
        chunks << "#{start}"
      end
      break
    end

    current = nos[i].to_i
    if prev
      if current > prev + 1
        chunks << "#{start}-#{prev}"
        start = current
        prev = nil
      elsif current == prev + 1
        prev = current
      end
      next
    else
      if current > start + 1
        chunks << "#{start}"
        start = current
      else 
        prev = current
      end
    end
  end
  chunks.join(',')
end


def chunk_nums_from_query(chunk_lists)
  chunks = []
  chunk_lists.each do |chunk_list|
    if chunk_list.match(/-/)
      (chunk_list.split('-')[0]..chunk_list.split('-')[1]).to_a.each{|chunk| chunks << chunk}
    else
      chunks << chunk_list
    end
  end
  chunks
end


def time_to_query?
  db_add = Redis.new(CONFIG.database_configuration.merge(:db => 10))
  last_queried = db_add.get "repoll_at"
  if last_queried.nil?
    db_add.set "repoll_at", (Time.now - 1)
  end
  return Time.parse(db_add.get "repoll_at") - Time.now < 0 ? true : false
end

def update_list
  url_for_lists = "/safebrowsing/list?"
  url_for_data = "/safebrowsing/downloads?"
  google_url = "http://safebrowsing.clients.google.com:80"
  DaemonKit.logger.info "Checking at #{Time.now}"
  db_add = Redis.new(CONFIG.database_configuration.merge(:db => CONFIG.add_db))
  db_sub = Redis.new(CONFIG.database_configuration.merge(:db => CONFIG.sub_db))

  last_queried = db_add.get "repoll_at"
  if last_queried.nil?
    db_add.set "repoll_at", (Time.now - 1)
  end

  unless Time.now > Time.parse(db_add.get "repoll_at")
    DaemonKit.logger.info "Not yet time to query the database. Its still #{Time.now}, query at or after #{db_add.get 'repoll_at'}."
    db_add.quit
    db_sub.quit
    return
  else
    started_at = Time.now
    uri = URI.parse(google_url)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new("#{url_for_lists}client=#{CONFIG.client}&apikey=#{CONFIG.apikey}&appver=#{CONFIG.clientver}&pver=#{CONFIG.pver}")

    # Body of the request cannot be nil has to be something, but it will be ignored. :)
    request.body = ""
    response = http.request(request)
#    puts response.body

    request = Net::HTTP::Post.new("#{url_for_data}client=#{CONFIG.client}&apikey=#{CONFIG.apikey}&appver=#{CONFIG.clientver}&pver=#{CONFIG.pver}")

    present_add_chunks = get_chunknum_query((db_add.smembers "add_chunk").sort)
    present_sub_chunks = get_chunknum_query((db_sub.smembers "sub_chunk").sort)

    request.body = "goog-malware-shavar;"
    unless present_add_chunks.empty?
      request.body += "a:#{present_add_chunks}"
    end

    unless present_sub_chunks.empty?
      request.body += ":" if present_add_chunks
      request.body += "s:#{present_sub_chunks}"
    end
    DaemonKit.logger.info "Requesting body - #{request.body}"
    request.body += "\n"
    queried_at = Time.now
    response = http.request(request)
    DaemonKit.logger.info "Response = #{response.code}"    
    repoll_in = nil
    list_name = nil
    redirect_urls = []
    remove_add_chunks = []
    remove_sub_chunks = []

    lines = response.body.split("\n")
    lines.each do |line|
      data = line.split(":")
      keyword = data[0]
      case keyword
        when "n"
          repoll_in = data[1]
        when "i"
          list_name = data[1]
        when "u"
          redirect_urls << data[1]
        when "ad"
          remove_add_chunks << data[1]
        when "sd"
          remove_sub_chunks << data[1]
        else
          DaemonKit.logger.info "Got unusual keyword #{keyword}"
      end 
    end
    next_query_at = queried_at + repoll_in.to_i
    db_add.set "repoll_at", next_query_at

    DaemonKit.logger.info "Removing add_chunk #{remove_add_chunks.join(', ')}"
    chunk_nums_from_query(remove_add_chunks).each do |chunk|
      (db_add.smembers chunk).each do |host_key|
        (db_add.smembers host_key).each do |prefix|
          db_add.srem host_key, prefix
          db_add.srem "add_prefix", prefix
        end
        db_add.srem "add_host", host_key
      end
      db_add.srem "add_chunk", chunk
    end
    

    DaemonKit.logger.info "Removing sub_chunk #{remove_sub_chunks.join(', ')}"    
    chunk_nums_from_query(remove_sub_chunks).each do |chunk|
      (db_sub.smembers chunk).each do |host_key|
        (db_sub.smembers host_key).each do |add_chunk|
          (db_sub.smembers add_chunk).each do |prefix|
            db_sub.srem add_chunk, prefix
            db_sub.srem "sub_prefix", prefix
          end
          db_sub.srem host_key, add_chunk
          db_sub.srem "add_chunk", add_chunk
        end
        db_sub.srem "sub_host", host_key
      end
      db_sub.srem "sub_chunk", chunk
    end
    
#    puts "Got redirect google_urlS - "
#    redirect_urls.each{|url| puts url}
    add_hostkeys = {}
    sub_hostkeys = {}

    add = {}
    sub = {}

    redirect_urls.each do |redirect_url|
      request = Net::HTTP::Get.new("#{redirect_url}")
      DaemonKit.logger.info "Processing google_url - #{redirect_url}"
      response = http.request(request)
      body = response.body
      while body.length > 0
        head = get_head_data(body)
        head_type = head[1]
        chunknum = head[2].to_i
        hashlen = head[3].to_i
        chunklen = head[4].to_i
        head_length = head.to_s.length
        body = body.sub(head.to_s, "")
        if chunklen > 0
          chunkdata = body[0..(chunklen-1)]
        else
          chunkdata = ""
        end
    #    puts "Got \"#{head_type}\" of chunknum #{chunknum} hash length #{hashlen} chunk length #{chunklen}"
        case head_type
        when "a"
          db_add.sadd "add_chunk", chunknum
        when "s"
          db_sub.sadd "sub_chunk", chunknum
        else
          DaemonKit.logger.info "Got odd head type #{head_type}"
        end
        data = chunkdata


        case head_type
        when "a"
          add_hosts = get_add_data(data, hashlen)
          add = add.join_merge(add_hosts)
#          DaemonKit.logger.info add
        when "s"
          sub_hosts = get_sub_data(data, hashlen)
          sub = sub.join_merge(sub_hosts)
#          DaemonKit.logger.info sub
        end
        body = body.sub(chunkdata, "")
      end
      # Dump data into database
      
      case head_type
      when "a"
        add.each do |host_key, prefixes|
#          DaemonKit.logger.info "For 'a' - #{host_key} got #{prefixes.join(', ')}"
    	    db_add.sadd "add_host", host_key
          db_add.sadd chunknum, host_key
          prefixes.each do |prefix|
            db_add.sadd "add_prefix", prefix
            db_add.sadd host_key, prefix
          end
        end
      when "s"
        sub.each do |host_key, chunk_prefixes|
#          DaemonKit.logger.info "For 's' - #{host_key}"
          db_sub.sadd "sub_host", host_key
          chunk_prefixes.each do |chunk_prefix|
            chunk_prefix.each do |chunk, prefix|
              db_sub.sadd host_key, chunk
	            db_sub.sadd "add_chunk", chunk
              next if prefix.nil?
              db_sub.sadd "sub_prefix", prefix
        	    db_sub.sadd chunk, prefix
            end
          end
        end
      end
      add = {}
      sub = {}
    end
    DaemonKit.logger.info "Started at #{started_at} and completed at #{Time.now}"
    DaemonKit.logger.info "Got #{db_add.scard 'add_host'} add hosts, #{db_sub.scard 'sub_host'} sub hosts"
    DaemonKit.logger.info "Got #{db_add.scard 'add_prefix'} add prefixes, #{db_sub.scard 'sub_prefix'} sub prefixes"
    DaemonKit.logger.info "Got add_chunks #{get_chunknum_query((db_add.smembers 'add_chunk').sort)} AND sub_chunks #{get_chunknum_query((db_sub.smembers 'sub_chunk').sort)}"
    DaemonKit.logger.info "Next poll at #{next_query_at}"

    db_add.quit
    db_sub.quit
  end
end

def query_for_full_hash(prefixes)
  all_prefixes = prefixes.join
  each_prefix_length = 4
  prefixes_length = each_prefix_length * prefixes.length
  req_for_full_hash = "/safebrowsing/gethash?"
  uri = URI.parse("http://safebrowsing.clients.google.com:80")
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new("#{req_for_full_hash}client=#{CONFIG.client}&apikey=#{CONFIG.apikey}&appver=#{CONFIG.clientver}&pver=#{CONFIG.pver}")
  puts "#{req_for_full_hash}client=#{CONFIG.client}&apikey=#{CONFIG.apikey}&appver=#{CONFIG.clientver}&pver=#{CONFIG.pver}"
  request.body = "#{each_prefix_length}:#{prefixes_length}\n#{all_prefixes}"
  # puts request.body
  response = http.request(request)
  puts response.body
  full_hashes = {}
  if response.code == "200"
    full_hashes = get_full_hash(response.body)
  elsif response.code == "204"
    return {}
  else
    DaemonKit.logger.info "Got response for full length hash as #{response.code}"
  end
  puts full_hashes
  full_hashes
end
