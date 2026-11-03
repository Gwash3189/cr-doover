# cr-doover

A fluent, type-safe retry library for Crystal with configurable backoff, full jitter, and lifecycle hooks.

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

## Testing

Run the test suite with:

```bash
crystal spec
```

## Benchmarking

Measure the performance of `Doover::Backoff.compute` for each strategy with:

```bash
crystal run --release bench/backoff_bench.cr
```

The benchmark uses a seeded random source for jitter and a short IPS
configuration, so it completes in a few seconds.
