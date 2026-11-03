require "spec"
require "../src/doover"

class DooverRecordingSleeper
  getter sleeps = [] of Time::Span

  def record(span : Time::Span) : Nil
    @sleeps << span
  end

  def count : Int32
    @sleeps.size
  end
end

class DooverTransientError < Exception
end

class DooverFatalError < Exception
end

class DooverFixedRandom
  include Random

  def initialize(@value : Float64)
  end

  def next_u : UInt32
    0_u32
  end

  def next_float : Float64
    @value
  end
end
