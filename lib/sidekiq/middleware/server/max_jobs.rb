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
          def cache
            @cache ||= {}
          end

          def counter
            key = counter_key
            cache[key] ||= 0
          end

          def counter_for_queue(queue)
            key = counter_for_queue_key(queue)
            cache[key] ||= 0
          end

          def counter_for_queue_key(queue)
            "COUNTER_#{queue.upcase}"
          end

          def counter_key
            'COUNTER'
          end

          def default_max_jobs
            100
          end

          def default_max_jobs_jitter
            1
          end

          def increment_counter!
            key = counter_key
            cache[key] = (cache[key] || 0).next
          end

          def increment_counter_for_queue!(queue)
            key = counter_for_queue_key(queue)
            cache[key] = (cache[key] || 0).next
          end

          def log_info(message)
            ::Sidekiq.logger.info(message) if defined?(::Sidekiq.logger)
          end

          def log_initialization!
            log_info("Max-Jobs middleware enabled, shutting down pid: #{pid} when max-jobs quota is reached")
          end

          def max_jobs
            key = max_jobs_key
            cache[key] ||= (ENV[key] || default_max_jobs).to_i
          end

          def max_jobs_for_queue(queue)
            key = max_jobs_for_queue_key(queue)
            cache[key] ||= (
              ENV[key] ||
              ENV[max_jobs_key] ||
              default_max_jobs
            ).to_i
          end

          def max_jobs_for_queue_key(queue)
            "MAX_JOBS_#{queue.upcase}"
          end

          def max_jobs_jitter
            key = max_jobs_jitter_key
            cache[key] ||= rand((ENV[key] || default_max_jobs_jitter).to_i)
          end

          def max_jobs_jitter_for_queue(queue)
            key = max_jobs_jitter_for_queue_key(queue)
            cache[key] ||= rand(
              (
                ENV[key] ||
                ENV[max_jobs_jitter_key] ||
                default_max_jobs_jitter
              ).to_i
            )
          end

          def max_jobs_jitter_for_queue_key(queue)
            "MAX_JOBS_JITTER_#{queue.upcase}"
          end

          def max_jobs_jitter_key
            'MAX_JOBS_JITTER'
          end

          def max_jobs_key
            'MAX_JOBS'
          end

          def max_jobs_with_jitter
            key = max_jobs_with_jitter_key
            cache[key] ||= (max_jobs + max_jobs_jitter)
          end

          def max_jobs_with_jitter_for_queue(queue)
            key = max_jobs_with_jitter_for_queue_key(queue)
            cache[key] ||= \
              (max_jobs_for_queue(queue) + max_jobs_jitter_for_queue(queue))
          end

          def max_jobs_with_jitter_for_queue_key(queue)
            "MAX_JOBS_WITH_JITTER_#{queue.upcase}"
          end

          def max_jobs_with_jitter_key
            'MAX_JOBS_WITH_JITTER'
          end

          def mutex
            key = mutex_key
            cache[key] ||= ::Mutex.new
          end

          def mutex_key
            'MUTEX'
          end

          def pid
            key = pid_key
            cache[key] ||= ::Process.pid
          end

          def pid_key
            'PID'
          end

          def quota_met?
            counter == max_jobs_with_jitter
          end

          def quota_met_for_queue?(queue)
            counter_for_queue(queue) == max_jobs_with_jitter_for_queue(queue)
          end
        end

        def call(
          _,     # worker-instance
          _,     # item
          queue
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
                terminate = false

                # Increment the total counter
                self.class.increment_counter!

                # First check if the total quota has been met
                if self.class.quota_met?
                  self.class.log_info("Max-Jobs quota met, shutting down pid: #{self.class.pid}")
                  terminate = true
                end

                # Increment the queue specific counter
                self.class.increment_counter_for_queue!(queue)

                # Now check if the queue specific quota has been met
                if !terminate && self.class.quota_met_for_queue?(queue)
                  self.class.log_info(%(Max-Jobs quota met for queue: "#{queue}", shutting down pid: #{self.class.pid}))
                  terminate = true
                end

                # If applicable, TERMinate the `Process`
                ::Process.kill('TERM', self.class.pid) if terminate
              end
            end
          end
        end
      end
    end
  end
end

::Sidekiq::Middleware::Server::MaxJobs.log_initialization!
