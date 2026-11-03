# cr-doover

A fluent, type-safe retry library for Crystal with configurable backoff, full jitter, lifecycle hooks, and declarative instance-method wrapping.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     doover:
       github: Gwash3189/cr-doover
   ```

2. Run `shards install`

## Usage

```crystal
require "doover"

result = Doover
  .exponential
  .attempts(3)
  .delay(100.milliseconds)
  .jitter
  .max_delay(2.seconds)
  .work { |attempt| fetch_resource(attempt) }
  .on_retry do |error, attempt|
    Log.warn { "attempt #{attempt} failed: #{error.message}" }
    !error.is_a?(FatalError) # return false to abort immediately
  end
  .on_exhausted do |error, attempts|
    Log.error { "gave up after #{attempts} attempts" }
  end
  .run
```

Configuration methods can be called before or after `#work`.

## Strategies

- `Doover.exponential` (default): `delay * 2^(attempt - 1)`
- `Doover.linear`: `delay * attempt`
- `Doover.constant`: `delay` on every retry
- `Doover.immediate`: no delay

## Configuration

- `attempts(count)` — total number of work calls, including the first (default: `3`). `attempts(3)` allows at most two sleeps.
- `delay(span)` — base delay (default: `100.milliseconds`).
- `jitter(enabled = true)` — full jitter, sampling uniformly from `[0, calculated_delay]` (default: disabled).
- `max_delay(span)` — caps the calculated delay before jitter is applied.
- `random(source)` — inject a `Random` source for deterministic jitter.
- `sleep_with { |span| ... }` — replace the sleeper (useful in tests).
- `on_retry { |error, attempt| ... }` — runs after a failed attempt while retries remain, before sleeping. Return `false` to abort immediately; any other value continues.
- `on_exhausted { |error, attempts| ... }` — runs after the final failed attempt, before the original exception is re-raised.
- `work { |attempt| ... }` — provides the work function, receives a 1-indexed attempt number, and returns a typed `Runner`.
- `run` — executes the work and returns its result. A runner can be run repeatedly, starting over at attempt 1.

## Wrapping instance methods

`include Doover` adds a `do_over` declaration that wraps an instance method
with the same retry behavior. The declaration may appear before or after the
method definition.

```crystal
class Payments
  include Doover

  do_over method: :charge,
    strategy: :exponential,
    attempts: 3,
    delay: 100.milliseconds,
    jitter: true,
    max_delay: 2.seconds,
    on_retry: :charge_retry,
    on_exhausted: :charge_exhausted

  def charge(amount : Int32) : String
    # call the downstream payment service
  end

  private def charge_retry(error : Exception, attempt : Int32) : Bool
    !error.is_a?(FatalError) # return false to abort immediately
  end

  private def charge_exhausted(error : Exception, attempts : Int32) : Nil
    Log.error { "gave up after #{attempts} attempts" }
  end
end
```

The wrapper preserves the original method signature, including overloads,
default and named arguments, splat and double-splat arguments, `yield`-based
blocks, typed captured blocks, and private or protected visibility.

`do_over` accepts the same strategy, attempts, delay, jitter, and max-delay
options as the fluent API. It also accepts optional `sleeper:` and `random:`
method symbols, which are useful for deterministic tests:

```crystal
do_over method: :perform,
  strategy: :constant,
  attempts: 2,
  delay: 10.milliseconds,
  sleeper: :record_sleep,
  random: :random_source
```

The generated wrapper builds a fresh configuration per method call; retry
attempts themselves do not allocate.

Limitations:

- Only instance methods can be wrapped.
- The wrapped method must be declared on the same type that calls `do_over`.
- Abstract methods and operator methods are rejected at compile time.
- A captured block parameter must have a type restriction. Use an anonymous
  `&` block or `yield` when the block is not captured.

## Testing

Run the test suite with:

```bash
crystal spec
```

## Performance

`Runner#run` is allocation-free per attempt. Configuration is copied only
during builder setup, handler arrays are iterated in place, and delay
calculations return `Time::Span` values without intermediate objects.

Configurations guaranteed to have zero delay — the `immediate` strategy, a
non-positive base delay, or a non-positive `max_delay` — bypass both
`Backoff.compute` and the sleeper. When full jitter produces zero for a
non-zero base delay, the delay is still computed but the sleeper is skipped.

Measure delay calculation and runner overhead in release mode with:

```bash
crystal run --release bench/backoff_bench.cr
```

The benchmark uses a seeded random source and a short IPS configuration, so it
completes in a few seconds. Numbers vary by machine; run it locally for current
figures.
