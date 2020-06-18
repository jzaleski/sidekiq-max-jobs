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

          def counter(queue)
            key = counter_key(queue)
            return cache[key] if cache.include?(key)

            cache[key] = 0
          end

          def counter_key(queue)
            "COUNTER_#{queue.upcase}"
          end

          def increment_counter!(queue)
            key = counter_key(queue)
            counter = cache[key] || 0

            cache[key] = counter.next
          end

          def log_info(message)
            ::Sidekiq.logger.info(message) if defined?(::Sidekiq.logger)
          end

          def log_initialization!
            log_info("Max-Jobs middleware enabled, shutting down pid: #{pid} after max-jobs threshold reached")
          end

          def max_jobs(queue)
            key = max_jobs_key(queue)
            return cache[key] if cache.include?(key)

            cache[key] = (
              ENV[key] ||
              ENV['MAX_JOBS'] ||
              100
            ).to_i
          end

          def max_jobs_key(queue)
            "MAX_JOBS_#{queue.upcase}"
          end

          def max_jobs_jitter(queue)
            key = max_jobs_jitter_key(queue)
            return cache[key] if cache.include?(key)

            cache[key] = rand(
              (
                ENV[key] ||
                ENV['MAX_JOBS_JITTER'] ||
                1
              ).to_i
            )
          end

          def max_jobs_jitter_key(queue)
            "MAX_JOBS_JITTER_#{queue.upcase}"
          end

          def max_jobs_with_jitter(queue)
            key = max_jobs_with_jitter_key(queue)
            return cache[key] if cache.include?(key)

            cache[key] = max_jobs(queue) + max_jobs_jitter(queue)
          end

          def max_jobs_with_jitter_key(queue)
            "MAX_JOBS_WITH_JITTER_#{queue.upcase}"
          end

          def mutex(queue)
            key = mutex_key(queue)
            return cache[key] if cache.include?(key)

            cache[key] = ::Mutex.new
          end

          def mutex_key(queue)
            "MUTEX_#{queue.upcase}"
          end

          def pid
            @pid ||= ::Process.pid
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
              self.class.mutex(queue).synchronize do
                self.class.increment_counter!(queue)

                if self.class.counter(queue) == self.class.max_jobs_with_jitter(queue)
                  self.class.log_info("Max-Jobs quota met, shutting down pid: #{self.class.pid}")
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
