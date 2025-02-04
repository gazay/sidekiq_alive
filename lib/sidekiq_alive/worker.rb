# frozen_string_literal: true

module SidekiqAlive
  class Worker
    include Sidekiq::Worker
    sidekiq_options retry: false

    # Passing the hostname argument it's only for debugging enqueued jobs
    def perform(_hostname = SidekiqAlive.hostname)
      if _hostname != current_hostname
        SidekiqAlive.logger.info("Wrong sidekiq alive instance, rescheduling..")
        self.class.perform_async(current_hostname)
        return
      end

      SidekiqAlive.logger.info("Performing SidekiqAlive::Worker for #{current_hostname}")
      # Checks if custom liveness probe passes should fail or return false
      return unless config.custom_liveness_probe.call

      # Writes the liveness in Redis
      write_living_probe
      # schedules next living probe
      SidekiqAlive.logger.info("Scheduling next living probe in #{(config.time_to_live / 2).round} seconds")
      self.class.perform_in(config.time_to_live / 2, current_hostname)
    end

    def write_living_probe
      # Purge extra and old jobs
      SidekiqAlive.purge_pending_jobs
      # Write liveness probe
      SidekiqAlive.store_alive_key
      # Increment ttl for current registered instance
      SidekiqAlive.register_current_instance
      # after callbacks
      begin
        config.callback.call
      rescue StandardError
        nil
      end
    end

    def current_hostname
      SidekiqAlive.hostname
    end

    def config
      SidekiqAlive.config
    end
  end
end
