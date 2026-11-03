module Doover
  # The backoff strategy used to calculate the delay between attempts.
  enum Strategy
    Exponential
    Linear
    Constant
    Immediate
  end
end
