module Doover
  # Calculates the delay between attempts using the configured strategy.
  module Backoff
    extend self

    private NANOSECONDS_PER_SECOND   = 1_000_000_000_i64
    private NANOSECONDS_PER_SECOND_F =   1_000_000_000.0

    # Returns the delay before the next attempt.
    #
    # *attempt* is 1-indexed. Full jitter samples uniformly from
    # `[0, calculated_delay]` after the calculated delay has been capped by
    # *max_delay*. Arithmetic saturates at `Time::Span::MAX` (or the configured
    # cap) instead of overflowing.
    def compute(
      strategy : Strategy,
      base_delay : Time::Span,
      attempt : Int32,
      jitter : Bool = false,
      max_delay : Time::Span? = nil,
      random : Random = Random.new,
    ) : Time::Span
      return Time::Span.zero if strategy.immediate?
      return Time::Span.zero if base_delay <= Time::Span.zero

      attempt = 1 if attempt < 1

      delay = case strategy
              when .exponential?
                exponential(base_delay, attempt - 1)
              when .linear?
                linear(base_delay, attempt)
              when .constant?
                base_delay
              else
                Time::Span.zero
              end

      delay = capped(delay, max_delay)
      delay = apply_jitter(delay, random) if jitter
      delay
    end

    private def exponential(base : Time::Span, exponent : Int32) : Time::Span
      return base if exponent <= 0

      seconds = base.to_i
      nanoseconds = base.nanoseconds.to_i64
      remaining = exponent

      while remaining > 0
        nanoseconds *= 2
        carry = nanoseconds // NANOSECONDS_PER_SECOND
        nanoseconds %= NANOSECONDS_PER_SECOND

        return Time::Span::MAX if seconds > (Int64::MAX - carry) // 2

        seconds = seconds * 2 + carry
        remaining -= 1
      end

      Time::Span.new(seconds: seconds, nanoseconds: nanoseconds)
    end

    private def linear(base : Time::Span, attempt : Int32) : Time::Span
      return base if attempt <= 1

      seconds = base.to_i
      nanoseconds = base.nanoseconds.to_i64 * attempt
      carry = nanoseconds // NANOSECONDS_PER_SECOND
      nanoseconds %= NANOSECONDS_PER_SECOND

      return Time::Span::MAX if seconds > (Int64::MAX - carry) // attempt

      Time::Span.new(seconds: seconds * attempt + carry, nanoseconds: nanoseconds)
    end

    private def capped(delay : Time::Span, max_delay : Time::Span?) : Time::Span
      if max = max_delay
        return max if delay > max
      end

      delay
    end

    private def apply_jitter(delay : Time::Span, random : Random) : Time::Span
      return Time::Span.zero if delay <= Time::Span.zero

      factor = random.next_float
      return Time::Span.zero if factor <= 0.0
      return delay if factor >= 1.0

      span_from_nanoseconds(delay.total_nanoseconds * factor)
    end

    private def span_from_nanoseconds(nanoseconds : Float64) : Time::Span
      return Time::Span.zero if nanoseconds <= 0.0
      return Time::Span::MAX if nanoseconds >= Time::Span::MAX.total_nanoseconds

      if nanoseconds < Int64::MAX.to_f64
        Time::Span.new(nanoseconds: nanoseconds.to_i64)
      else
        seconds = (nanoseconds / NANOSECONDS_PER_SECOND_F).floor
        remainder = nanoseconds - (seconds * NANOSECONDS_PER_SECOND_F)
        Time::Span.new(seconds: seconds.to_i64, nanoseconds: remainder.to_i64)
      end
    end
  end
end
