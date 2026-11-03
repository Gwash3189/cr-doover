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
