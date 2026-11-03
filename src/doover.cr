# `Doover` provides an intuitive, idiomatic API for retrying any Crystal block
# with configurable retry limits, base delay, exponential backoff, and jitter.
#
# ### Basic Usage
#
# ```
# require "doover"
#
# retry(limit: 3, backoff: true, jitter: true, delay: 3.seconds) do |error|
#   if error
#     # Handle or log the error from the previous failed attempt
#     STDERR.puts "Attempt failed (#{error.message}), retrying..."
#   end
#
#   # Your fallible logic here
#   fetch_remote_resource()
# end
# ```
module Doover
  VERSION = "0.2.0"

  # Executes the given block and retries up to `limit` times when an exception is raised.
  #
  # Yields `last_error : Exception?` (which is `nil` on the initial attempt and
  # set to the most recently caught `Exception` on subsequent retry attempts)
  # and `attempt : Int32` (1-indexed attempt number).
  def self.run(
    limit : Int32 = 3,
    delay : Time::Span = 1.second,
    backoff : Bool | Number = false,
    jitter : Bool | Float64 = false,
    max_delay : Time::Span? = nil,
    only = {Exception},
    except = Tuple.new,
    on_retry = nil,
    random : Random = Random::DEFAULT,
    sleeper = ->(span : Time::Span) { sleep(span) },
    &
  )
    raise ArgumentError.new("limit must be >= 0 (got #{limit})") if limit < 0
    raise ArgumentError.new("delay must be >= 0 (got #{delay})") if delay < Time::Span.zero

    attempt = 0
    last_error : Exception? = nil

    loop do
      attempt += 1
      begin
        return yield last_error, attempt
      rescue ex : Exception
        raise ex unless should_retry?(ex, only, except)
        raise ex if attempt > limit

        last_error = ex
        wait_time = compute_delay(
          retry_number: attempt,
          base_delay: delay,
          backoff: backoff,
          jitter: jitter,
          max_delay: max_delay,
          random: random
        )

        on_retry.try(&.call(ex, attempt, wait_time))
        sleeper.call(wait_time) if wait_time > Time::Span.zero
      end
    end
  end

  # Computes the wait `Time::Span` for a given `retry_number` (1-indexed).
  def self.compute_delay(
    retry_number : Int32,
    base_delay : Time::Span,
    backoff : Bool | Number = false,
    jitter : Bool | Float64 = false,
    max_delay : Time::Span? = nil,
    random : Random = Random::DEFAULT,
  ) : Time::Span
    return Time::Span.zero if base_delay <= Time::Span.zero

    seconds = base_delay.total_seconds

    factor = case backoff
             when Bool
               backoff ? 2.0 : 1.0
             when Number
               backoff.to_f64
             else
               1.0
             end

    if factor > 1.0 && retry_number > 1
      seconds *= factor ** (retry_number - 1)
    end

    if max = max_delay
      seconds = Math.min(seconds, max.total_seconds)
    end

    jitter_ratio = case jitter
                   when Bool
                     jitter ? 0.5 : 0.0
                   when Float64
                     jitter.clamp(0.0, 1.0)
                   else
                     0.0
                   end

    if jitter_ratio > 0.0
      # Apply uniform jitter in the range [seconds * (1 - jitter_ratio), seconds * (1 + jitter_ratio)]
      min_factor = 1.0 - jitter_ratio
      max_factor = 1.0 + jitter_ratio
      multiplier = min_factor + random.next_float * (max_factor - min_factor)
      seconds *= multiplier
    end

    if max = max_delay
      seconds = Math.min(seconds, max.total_seconds)
    end

    Time::Span.new(nanoseconds: (seconds * 1_000_000_000.0).to_i64)
  end

  private def self.should_retry?(ex : Exception, only, except) : Bool
    except.each do |ignored_class|
      return false if ignored_class === ex
    end

    only.each do |allowed_class|
      return true if allowed_class === ex
    end

    false
  end
end

# Top-level `retry` helper delegating to `Doover.run`.
def retry(
  limit : Int32 = 3,
  delay : Time::Span = 1.second,
  backoff : Bool | Number = false,
  jitter : Bool | Float64 = false,
  max_delay : Time::Span? = nil,
  only = {Exception},
  except = Tuple.new,
  on_retry = nil,
  random : Random = Random::DEFAULT,
  sleeper = ->(span : Time::Span) { sleep(span) },
  &
)
  Doover.run(
    limit: limit,
    delay: delay,
    backoff: backoff,
    jitter: jitter,
    max_delay: max_delay,
    only: only,
    except: except,
    on_retry: on_retry,
    random: random,
    sleeper: sleeper
  ) do |error, attempt|
    yield error, attempt
  end
end
