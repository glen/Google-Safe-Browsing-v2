class RequestHandler < EventMachine::Connection
  include EventMachine::HttpServer

  def process_http_request
    resp = EventMachine::DelegatedHttpResponse.new( self )
    # Block which fulfills the request
    operation = proc do
      request = @http_request_uri.sub("/", "")
      request_type = @http_request_method
      resp.status  = 200
      if request_type == "GET"
        case request
        when "url_status"
          query_string = @http_query_string || ""
          url = URI.decode(query_string.sub("url=", "").strip)
          if url.empty?
            resp.content = {"status" => "Error. Query to be in form #{CONFIG.server}:#{CONFIG.port}/url_status?url=http://www.google.com"}.to_json
          else
            if DbHelper.clean?(url)
#              DaemonKit.logger.info "#{url} is Safe!"
              resp.content = {:url => url, :status => "Clean"}.to_json
            else
              DaemonKit.logger.info "#{url} is Unsafe!"
              resp.content = {:url => url, :status => "Dirty"}.to_json
            end
          end          
        else
          DaemonKit.logger.info "Incorrect request"
          resp.content = "Incorrect request sent"
        end
      end
    end

    # Callback block to execute once the request is fulfilled
    callback = proc do |res|
    	resp.send_response
    end
 
    # Let the thread pool (20 Ruby threads) handle request
    EM.defer(operation, callback)    
  end

end
