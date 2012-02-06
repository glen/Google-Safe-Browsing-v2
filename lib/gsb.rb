# Your starting point for daemon specific classes. This directory is
# already included in your load path, so no need to specify it.

EM.run do
  EventMachine.epoll
  EventMachine::start_server("0.0.0.0", CONFIG.port, RequestHandler)
  DaemonKit.logger.info "Started on port #{CONFIG.port}"

  EM.add_periodic_timer(CONFIG.check_for_update) do
    Thread.new do
      DaemonKit.logger.info "Checking if time to query.."
      update_list if time_to_query?
    end
  end

end
