require "benchmark"
require "../src/doover"

class DooverBenchError < Exception
end

base_delay = 100.milliseconds
max_delay = 5.seconds
random = Random.new(1234)

# Build runners before the benchmark blocks so setup work is not measured.
# Retry reports include the cost of raising the work exception; the runner
# itself does not allocate per attempt.
success_runner = Doover.immediate.work { 1 }
retry_runner = Doover.immediate
  .attempts(3)
  .work do |attempt|
    raise DooverBenchError.new("retry") if attempt < 3
    attempt
  end
zero_delay_runner = Doover.constant
  .delay(Time::Span.zero)
  .attempts(3)
  .work do |attempt|
    raise DooverBenchError.new("retry") if attempt < 3
    attempt
  end

Benchmark.ips(calculation: 300.milliseconds, warmup: 100.milliseconds, interactive: false) do |x|
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

  x.report("runner: immediate success") do
    success_runner.run
  end

  x.report("runner: immediate retries") do
    retry_runner.run
  end

  x.report("runner: zero base delay retries") do
    zero_delay_runner.run
  end
end
