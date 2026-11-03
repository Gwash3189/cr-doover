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
    #
    # The retry loop reads `@config` in place and iterates handler arrays
    # without copying them, so it allocates nothing per attempt.
    def run : T
      Doover.__doover_retry(@config) do
        @work.call(__doover_attempt)
      end
    end
  end
end
