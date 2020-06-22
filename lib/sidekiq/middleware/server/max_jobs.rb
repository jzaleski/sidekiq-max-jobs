# frozen_string_literal: true

module Sidekiq
  module Middleware
    module Server
      class MaxJobs
        # Version

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
          # Constant(s)

          COUNTER_FOR_QUEUE_KEY_TEMPLATE = 'COUNTER_%s'
          COUNTER_KEY = 'COUNTER'
          LOG_INITIALIZATION_TEMPLATE = \
            'Max-Jobs middleware enabled, shutting down pid: %d when quota is reached'
          LOG_MAX_JOBS_QUOTA_MET_FOR_QUEUE_TEMPLATE = \
            'Max-Jobs queue quota met for: "%s", shutting down pid: %d'
          LOG_MAX_JOBS_QUOTA_MET_TEMPLATE = \
            'Max-Jobs total quota met, shutting down pid: %d'
          LOG_MAX_JOBS_RUNTIME_QUOTA_MET_TEMPLATE = \
            'Max-Jobs runtime quota met, shutting down pid: %d'
          MAX_JOBS_FOR_QUEUE_KEY_TEMPLATE = 'MAX_JOBS_%s'
          MAX_JOBS_JITTER_FOR_QUEUE_KEY_TEMPLATE = 'MAX_JOBS_JITTER_%s'
          MAX_JOBS_JITTER_KEY = 'MAX_JOBS_JITTER'
          MAX_JOBS_KEY = 'MAX_JOBS'
          MAX_JOBS_RUNTIME_JITTER_KEY = 'MAX_JOBS_RUNTIME_JITTER'
          MAX_JOBS_RUNTIME_WITH_JITTER_KEY = 'MAX_JOBS_RUNTIME_WITH_JITTER'
          MAX_JOBS_RUNTIME_KEY = 'MAX_JOBS_RUNTIME'
          MAX_JOBS_WITH_JITTER_FOR_QUEUE_KEY_TEMPLATE = \
            'MAX_JOBS_WITH_JITTER_%s'
          MAX_JOBS_WITH_JITTER_KEY = 'MAX_JOBS_WITH_JITTER'
          MUTEX_KEY = 'MUTEX'
          PID_KEY = 'PID'
          START_TIME_KEY = 'START_TIME'
          TERM = 'TERM'
          TERMINATING_KEY = 'TERMINATING'

          # Default(s)

          DEFAULT_MAX_JOBS = 500
          DEFAULT_MAX_JOBS_FOR_QUEUE = -1
          DEFAULT_MAX_JOBS_JITTER = -1
          DEFAULT_MAX_JOBS_JITTER_FOR_QUEUE = -1
          DEFAULT_MAX_JOBS_RUNTIME = -1
          DEFAULT_MAX_JOBS_RUNTIME_JITTER = -1

          # Helper Method(s)

          def cache
            @cache ||= {}
          end

          def counter
            key = COUNTER_KEY
            cache[key] ||= 0
          end

          def counter_for_queue(queue)
            key = format(COUNTER_FOR_QUEUE_KEY_TEMPLATE, queue.upcase)
            cache[key] ||= 0
          end

          def increment_counter!
            key = COUNTER_KEY
            cache[key] = (cache[key] || 0).next
          end

          def increment_counter_for_queue!(queue)
            key = format(COUNTER_FOR_QUEUE_KEY_TEMPLATE, queue.upcase)
            cache[key] = (cache[key] || 0).next
          end

          def log_info(message)
            logger_defined = defined?(::Sidekiq.logger)
            logger_defined ? ::Sidekiq.logger.info(message) : puts(message)
          end

          def log_initialization!
            message = format(LOG_INITIALIZATION_TEMPLATE, pid)
            log_info(message)
          end

          def log_max_jobs_quota_met!
            message = format(LOG_MAX_JOBS_QUOTA_MET_TEMPLATE, pid)
            log_info(message)
          end

          def log_max_jobs_quota_met_for_queue!(queue)
            message = format(
              LOG_MAX_JOBS_QUOTA_MET_FOR_QUEUE_TEMPLATE,
              queue,
              pid
            )
            log_info(message)
          end

          def log_max_jobs_runtime_quota_met!
            message = format(LOG_MAX_JOBS_RUNTIME_QUOTA_MET_TEMPLATE, pid)
            log_info(message)
          end

          def max_jobs
            key = MAX_JOBS_KEY
            cache[key] ||= (ENV[key] || DEFAULT_MAX_JOBS).to_i
          end

          def max_jobs_for_queue(queue)
            key = format(MAX_JOBS_FOR_QUEUE_KEY_TEMPLATE, queue.upcase)
            cache[key] ||= (ENV[key] || DEFAULT_MAX_JOBS_FOR_QUEUE).to_i
          end

          def max_jobs_jitter
            key = MAX_JOBS_JITTER_KEY
            cache[key] ||= rand((ENV[key] || DEFAULT_MAX_JOBS_JITTER).to_i)
          end

          def max_jobs_jitter_for_queue(queue)
            key = format(MAX_JOBS_JITTER_FOR_QUEUE_KEY_TEMPLATE, queue.upcase)
            cache[key] ||= \
              rand((ENV[key] || DEFAULT_MAX_JOBS_JITTER_FOR_QUEUE).to_i)
          end

          def max_jobs_quota_met?
            quota = max_jobs_with_jitter
            quota.positive? ? counter == quota : false
          end

          def max_jobs_quota_met_for_queue?(queue)
            quota = max_jobs_with_jitter_for_queue(queue)
            quota.positive? ? counter_for_queue(queue) == quota : false
          end

          def max_jobs_runtime
            key = MAX_JOBS_RUNTIME_KEY
            cache[key] ||= (ENV[key] || DEFAULT_MAX_JOBS_RUNTIME).to_i
          end

          def max_jobs_runtime_jitter
            key = MAX_JOBS_RUNTIME_JITTER_KEY
            cache[key] ||= \
              rand((ENV[key] || DEFAULT_MAX_JOBS_RUNTIME_JITTER).to_i)
          end

          def max_jobs_runtime_quota_met?
            quota = max_jobs_runtime_with_jitter
            quota.positive? ? (::Time.now.to_i - start_time) >= quota : false
          end

          def max_jobs_runtime_with_jitter
            key = MAX_JOBS_RUNTIME_WITH_JITTER_KEY
            cache[key] ||= (max_jobs_runtime + max_jobs_runtime_jitter)
          end

          def max_jobs_with_jitter
            key = MAX_JOBS_WITH_JITTER_KEY
            cache[key] ||= (max_jobs + max_jobs_jitter)
          end

          def max_jobs_with_jitter_for_queue(queue)
            key = \
              format(MAX_JOBS_WITH_JITTER_FOR_QUEUE_KEY_TEMPLATE, queue.upcase)
            cache[key] ||= \
              (max_jobs_for_queue(queue) + max_jobs_jitter_for_queue(queue))
          end

          def mutex
            key = MUTEX_KEY
            cache[key] ||= ::Mutex.new
          end

          def pid
            key = PID_KEY
            cache[key] ||= ::Process.pid
          end

          def start_time
            key = START_TIME_KEY
            cache[key] ||= ::Time.now.to_i
          end

          def terminate!
            key = TERMINATING_KEY
            cache[key] = true && ::Process.kill(TERM, pid)
          end

          def terminating?
            key = TERMINATING_KEY
            cache[key] == true
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
            # Set the `exception_raised` boolean to `true` so that the counter
            # *is not* incremented in the `ensure` block
            exception_raised = true
            # Re-raise the `Exception` so that _Sidekiq_ can deal w/ it
            raise
          ensure
            if !exception_raised && !self.class.terminating?
              self.class.mutex.synchronize do
                # Controls whether or not the process will be TERMinated at the
                # end of the block
                terminate = false

                # First check if the runtime quota has been met
                if self.class.max_jobs_runtime_quota_met?
                  self.class.log_max_jobs_runtime_quota_met!
                  terminate = true
                end

                # Increment the total counter
                self.class.increment_counter!

                # Next, check if the total quota has been met
                if !terminate && self.class.max_jobs_quota_met?
                  self.class.log_max_jobs_quota_met!
                  terminate = true
                end

                # Increment the queue specific counter
                self.class.increment_counter_for_queue!(queue)

                # Last[ly], check if the queue quota has been met
                if !terminate && self.class.max_jobs_quota_met_for_queue?(queue)
                  self.class.log_max_jobs_quota_met_for_queue!(queue)
                  terminate = true
                end

                # If applicable, terminate
                self.class.terminate! if terminate
              end
            end
          end
        end
      end
    end
  end
end

::Sidekiq::Middleware::Server::MaxJobs.log_initialization!
