require "benchmark"
require "../src/doover"

base_delay = 100.milliseconds
max_delay = 5.seconds
random = Random.new(1234)

Benchmark.ips(calculation: 1.second, warmup: 200.milliseconds, interactive: false) do |x|
  x.report("exponential") do
    Doover::Backoff.compute(Doover::Strategy::Exponential, base_delay, 5)
  end

  x.report("linear") do
    Doover::Backoff.compute(Doover::Strategy::Linear, base_delay, 5)
  end

  x.report("constant") do
    Doover::Backoff.compute(Doover::Strategy::Constant, base_delay, 5)
  end

  x.report("immediate") do
    Doover::Backoff.compute(Doover::Strategy::Immediate, base_delay, 5)
  end

  x.report("exponential with max_delay") do
    Doover::Backoff.compute(
      Doover::Strategy::Exponential,
      base_delay,
      10,
      max_delay: max_delay
    )
  end

  x.report("exponential with full jitter") do
    Doover::Backoff.compute(
      Doover::Strategy::Exponential,
      base_delay,
      5,
      jitter: true,
      random: random
    )
  end
end
