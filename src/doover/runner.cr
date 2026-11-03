module Doover
  # Executes typed work with retries according to its `Config`.
  #
  # A runner is reusable: every call to `#run` starts again at attempt 1.
  struct Runner(T)
    include Configurable

    getter config : Config

    def initialize(@config : Config, @work : Proc(Int32, T))
    end

    def with_config(config : Config) : self
      Runner(T).new(config, @work)
    end

    # Runs the work function until it succeeds or the configured attempts are
    # exhausted, returning the work result on success.
    def run : T
      attempt = 1

      loop do
        begin
          return @work.call(attempt)
        rescue error : Exception
          if attempt >= @config.attempts
            @config.exhausted_handlers.each do |handler|
              handler.call(error, attempt)
            end

            raise error
          end

          aborted = false
          @config.retry_handlers.each do |handler|
            unless handler.call(error, attempt)
              aborted = true
              break
            end
          end

          raise error if aborted

          wait = Backoff.compute(
            strategy: @config.strategy,
            base_delay: @config.base_delay,
            attempt: attempt,
            jitter: @config.jitter,
            max_delay: @config.max_delay,
            random: @config.random
          )

          @config.sleeper.call(wait) if wait > Time::Span.zero
          attempt += 1
        end
      end
    end
  end
end
