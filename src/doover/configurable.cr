module Doover
  # Configuration methods shared by `Builder` and `Runner`.
  #
  # Including types only need to expose the current `#config` and a
  # `#with_config` that returns the same type, which keeps the work function
  # type intact when configuring a `Runner`.
  module Configurable
    abstract def config : Config

    abstract def with_config(config : Config) : self

    # Sets the total number of attempts, including the first one.
    def attempts(count : Int32) : self
      raise ArgumentError.new("attempts must be at least 1 (got #{count})") if count < 1

      with_config(config.copy_with(attempts: count))
    end

    # Sets the base delay used by the backoff strategy.
    def delay(span : Time::Span) : self
      raise ArgumentError.new("delay must be non-negative (got #{span})") if span < Time::Span.zero

      with_config(config.copy_with(base_delay: span))
    end

    # Enables or disables full jitter.
    def jitter(enabled : Bool = true) : self
      with_config(config.copy_with(jitter: enabled))
    end

    # Caps the calculated delay before jitter is applied.
    def max_delay(span : Time::Span) : self
      raise ArgumentError.new("max_delay must be non-negative (got #{span})") if span < Time::Span.zero

      with_config(config.copy_with(max_delay: span))
    end

    # Replaces the random source used for jitter.
    def random(source : Random) : self
      with_config(config.copy_with(random: source))
    end

    # Replaces the function used to sleep between attempts.
    def sleep_with(&block : Time::Span -> _) : self
      sleeper = ->(span : Time::Span) do
        block.call(span)
        nil
      end

      with_config(config.copy_with(sleeper: sleeper))
    end

    # Registers a handler invoked after a failed attempt when retries remain.
    #
    # Returning `false` aborts retrying immediately; any other value continues.
    def on_retry(&block : Exception, Int32 -> _) : self
      handler = ->(error : Exception, attempt : Int32) do
        block.call(error, attempt) != false
      end

      with_config(config.with_retry_handler(handler))
    end

    # Registers a handler invoked after the final failed attempt.
    def on_exhausted(&block : Exception, Int32 -> _) : self
      handler = ->(error : Exception, attempt : Int32) do
        block.call(error, attempt)
        nil
      end

      with_config(config.with_exhausted_handler(handler))
    end
  end
end
