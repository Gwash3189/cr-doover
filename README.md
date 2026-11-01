# retry

An intuitive, idiomatic retry library for Crystal blocks with configurable retry limits, delays, exponential backoff, and jitter.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     retry:
       github: Gwash3189/retry
   ```

2. Run `shards install`

## Usage

```crystal
require "retry"

retry(limit: 3, backoff: true, jitter: true, delay: 3.seconds) do |error|
  if error
    STDERR.puts "Attempt failed (#{error.message}), retrying..."
  end

  # Your fallible logic here
  fetch_remote_resource()
end
```

### Options

- `limit` (`Int32`, default: `3`): Maximum number of retry attempts after initial failure.
- `delay` (`Time::Span`, default: `1.second`): Base wait time between attempts.
- `backoff` (`Bool | Number`, default: `false`): Enables exponential backoff (`2.0` multiplier when `true`, or custom multiplier).
- `jitter` (`Bool | Float64`, default: `false`): Adds uniform randomness (`±50%` when `true`, or custom ratio `0.0..1.0`) to prevent thundering herds.
- `max_delay` (`Time::Span?`, default: `nil`): Upper cap on delay duration.
- `only`: Exception types to catch and retry (default: `{Exception}`).
- `except`: Exception types to ignore and re-raise immediately.
- `on_retry`: Callback proc invoked with `(exception, retry_number, wait_span)` before sleeping.

## Testing

Run the test suite with:

```bash
crystal spec
```
