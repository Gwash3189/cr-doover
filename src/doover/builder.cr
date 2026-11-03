module Doover
  # A non-generic, fluent configuration builder.
  #
  # `#work` turns the builder into a typed `Runner(T)`, inferring `T` from the
  # work block. Configuration methods may be called before or after `#work`.
  struct Builder
    include Configurable

    getter config : Config

    def initialize(@config : Config = Config.new)
    end

    def with_config(config : Config) : self
      Builder.new(config)
    end

    # Captures the work function and returns a typed runner.
    def work(&block : Int32 -> T) : Runner(T) forall T
      Runner(T).new(config, block)
    end

    # A builder cannot run without work, so this always raises.
    def run : NoReturn
      raise ArgumentError.new("No work function provided. Call #work before #run.")
    end
  end

  # Starts a builder using exponential backoff.
  def self.exponential : Builder
    Builder.new(Config.new(strategy: Strategy::Exponential))
  end

  # Starts a builder using linear backoff.
  def self.linear : Builder
    Builder.new(Config.new(strategy: Strategy::Linear))
  end

  # Starts a builder using a constant delay.
  def self.constant : Builder
    Builder.new(Config.new(strategy: Strategy::Constant))
  end

  # Starts a builder that retries without sleeping.
  def self.immediate : Builder
    Builder.new(Config.new(strategy: Strategy::Immediate))
  end
end
