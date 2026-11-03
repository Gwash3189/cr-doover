module Doover
  # A normalized retry handler. Returns `false` to abort retrying.
  alias RetryHandler = Proc(Exception, Int32, Bool)

  # A handler invoked after the final failed attempt.
  alias ExhaustedHandler = Proc(Exception, Int32, Nil)

  # A function used to wait between attempts.
  alias Sleeper = Proc(Time::Span, Nil)

  # Immutable configuration shared by `Builder` and `Runner`.
  #
  # Every configuration operation returns a new `Config`; handler collections
  # are copied before being extended so existing configurations are never
  # mutated.
  struct Config
    getter strategy : Strategy
    getter attempts : Int32
    getter base_delay : Time::Span
    getter jitter : Bool
    getter max_delay : Time::Span?
    getter random : Random
    getter sleeper : Sleeper
    getter retry_handlers : Array(RetryHandler)
    getter exhausted_handlers : Array(ExhaustedHandler)

    def initialize(
      *,
      @strategy : Strategy = Strategy::Exponential,
      @attempts : Int32 = 3,
      @base_delay : Time::Span = 100.milliseconds,
      @jitter : Bool = false,
      @max_delay : Time::Span? = nil,
      @random : Random = Random.new,
      @sleeper : Sleeper = ->(span : Time::Span) { sleep(span) },
      @retry_handlers : Array(RetryHandler) = [] of RetryHandler,
      @exhausted_handlers : Array(ExhaustedHandler) = [] of ExhaustedHandler,
    )
    end

    def copy_with(
      *,
      strategy : Strategy = @strategy,
      attempts : Int32 = @attempts,
      base_delay : Time::Span = @base_delay,
      jitter : Bool = @jitter,
      max_delay : Time::Span? = @max_delay,
      random : Random = @random,
      sleeper : Sleeper = @sleeper,
      retry_handlers : Array(RetryHandler) = @retry_handlers,
      exhausted_handlers : Array(ExhaustedHandler) = @exhausted_handlers,
    ) : Config
      Config.new(
        strategy: strategy,
        attempts: attempts,
        base_delay: base_delay,
        jitter: jitter,
        max_delay: max_delay,
        random: random,
        sleeper: sleeper,
        retry_handlers: retry_handlers,
        exhausted_handlers: exhausted_handlers
      )
    end

    def with_retry_handler(handler : RetryHandler) : Config
      handlers = @retry_handlers.dup
      handlers << handler
      copy_with(retry_handlers: handlers)
    end

    def with_exhausted_handler(handler : ExhaustedHandler) : Config
      handlers = @exhausted_handlers.dup
      handlers << handler
      copy_with(exhausted_handlers: handlers)
    end
  end
end
