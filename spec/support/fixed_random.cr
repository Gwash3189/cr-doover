class DooverFixedRandom
  include Random

  getter calls = 0

  def initialize(@value : Float64)
  end

  def next_u : UInt32
    0_u32
  end

  def next_float : Float64
    @calls += 1
    @value
  end
end
