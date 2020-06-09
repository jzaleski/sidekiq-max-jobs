# frozen_string_literal: true

module Sidekiq
  module Middleware
    module Server
      class MaxJobs
        VERSION = File.read(
          File.join(
            File.dirname(__FILE__),
            '..',
            '..',
            '..',
            '..',
            'VERSION'
          )
        ).strip

        class << self
          def counter
            @counter ||= 0
          end

          def increment_counter!
            @counter += 1
          end

          def logger
            @logger ||= ::Sidekiq.logger
          end

          def log_initialization!
            logger.info("Max-Jobs middleware enabled, shutting down pid: #{pid} after: #{max_jobs_with_jitter} job(s)")
          end

          def max_jobs
            @max_jobs ||= (ENV['MAX_JOBS'] || 100).to_i
          end

          def max_jobs_jitter
            @max_jobs_jitter ||= rand((ENV['MAX_JOBS_JITTER'] || 1).to_i)
          end

          def max_jobs_with_jitter
            @max_jobs_with_jitter ||= max_jobs + max_jobs_jitter
          end

          def mutex
            @mutex ||= ::Mutex.new
          end

          def pid
            @pid ||= ::Process.pid
          end
        end

        def call(
          _,  # worker-instance
          _,  # item
          _   # queue
        )
          exception_raised = false
          begin
            yield
          rescue Exception
            # Set the `exception_raised` boolean to `true` so that the
            # job-counter *is not* incremented in the `ensure` block
            exception_raised = true
            # Re-raise the `Exception` so that _Sidekiq_ can deal w/ it
            raise
          ensure
            if !exception_raised
              self.class.mutex.synchronize do
                self.class.increment_counter!

                if self.class.counter == self.class.max_jobs_with_jitter
                  self.class.logger.info "Max-Jobs quota met, shutting down pid: #{self.class.pid}"
                  ::Process.kill('TERM', self.class.pid)
                end
              end
            end
          end
        end
      end
    end
  end
end

::Sidekiq::Middleware::Server::MaxJobs.log_initialization!
