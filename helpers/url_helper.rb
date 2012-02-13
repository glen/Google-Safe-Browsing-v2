module UrlHelper

  ##
  # We use a combination of Domainatrix and URI to reach a conclsion on the validity of a URL.
  # If Domainatrix parses the URL then it is sent to URI to parse.
  # If any fails then we consider that the url is malformed, else we assume it to be a valid url
  def self.malformed_url?(url)
    begin
#      DaemonKit.logger.info url
#      return false
      Domainatrix.parse(url) unless numeric_url?(url)
      begin     
        URI.parse(url)
        return false
      rescue URI::InvalidURIError
        DaemonKit.logger.info "Invalid URI Error"
        return true
      rescue Exception => e
        DaemonKit.logger.info "ERROR in malformed_url? for #{url} =>  #{e}"
        return true
      end
    rescue NoMethodError => e
      DaemonKit.logger.info "Domainatrix Error #{e.inspect}"
      return true
    rescue Exception => e
      DaemonKit.logger.info "ERROR in malformed_url? for #{url} =>  #{e}"
      return true
    end
  end

  def self.malformed_url?(url)
    url.match(/(.*):\/\/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\d{1,10}|[^\/]*)(\/.*)*/).nil?
  end

  ##
  # This method uses the Domainatrix gem to extract the domain of a given URL.
  # Many a times it throws an exception.
  # The known reasons are either the public domain is not listed or the URL is malformed.
  # In either case we return an empty string.
  #
  def self.extract_domain(url)
    # Check if it is a numeric URL and fetch the domain accordingly.
    if numeric_url?(url)
      website_domain_for_numeric_url(url)
    else
      Domainatrix.parse(url).domain
    end
  rescue
    ""
  end

  ##
  # Obtain the host of the url that is to be monitored
  def self.host(url)
    url.match(/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|\d{1,10}|[^\/]*)(\/.*)*/)[0]
  end

  ##
  # This method is used to check if an URL is numeric.
  # It matches the pattern https://xxx.xxx.xxx.xxx
  #
  def self.numeric_url?(url)
    true if url =~ /https?:\/\/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
  end


  ##
  # The domain in case of a numeric URL would be the IP itself.
  # This should be returned as the domain in case a website has a numeric URL.
  #
  def self.website_domain_for_numeric_url(url)
    domain_regex = %r{https?:\/\/(.+?)\/}
    domain = domain_regex.match(url)[1]
    domain
  end

end
