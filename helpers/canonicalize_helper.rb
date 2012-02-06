module Canonicalize

  def self.canonicalize(url)
#    input = url.encode('UTF-8')
    input = url.to_my_utf8
    input = input.strip
    input = input.gsub(/\\r|\\t|\\n/, '')
    input = "http://#{input}" if input.match(/\Awww/)
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
#    recursive_percent_escape(str.strip).encode('UTF-8').bytes{|byte|
    recursive_percent_escape(str.strip).to_my_utf8.bytes{|byte| 
  #    puts "#{byte.chr}"
      if byte <= 32 || byte >= 127 || byte == 35 || byte == 37
  #      puts "#{byte.chr} => #{byte} %#{byte.to_s(16).upcase}"
  #      clean_url << "%#{byte.to_s(16).upcase}"
			  byte.chr == "%" ? clean_url << byte.chr : clean_url << "%#{byte.to_s(16).upcase}"
      else
  #      puts byte
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
