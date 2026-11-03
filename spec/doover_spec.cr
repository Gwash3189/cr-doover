require "./spec_helper"

private class CustomTransientError < Exception
end

private class FatalAuthError < Exception
end

describe Doover do
  it "exposes the shard version" do
    Doover::VERSION.should eq("0.2.0")
  end

  it "executes the block once and returns its value when no error occurs" do
    attempts = 0
    seen_errors = [] of Exception?

    result = retry(limit: 3, delay: 3.seconds) do |error|
      seen_errors << error
      attempts += 1
      "ok"
    end

    result.should eq("ok")
    attempts.should eq(1)
    seen_errors.should eq([nil])
  end

  it "passes the previous error into the block on subsequent retries and succeeds" do
    attempts = 0
    recorded_errors = [] of String?
    sleeps = [] of Time::Span
    noop_sleeper = ->(span : Time::Span) { sleeps << span }

    result = retry(
      limit: 3,
      backoff: true,
      jitter: false,
      delay: 3.seconds,
      sleeper: noop_sleeper
    ) do |error|
      if error
        recorded_errors << error.message
      else
        recorded_errors << nil
      end

      attempts += 1
      raise "boom #{attempts}" if attempts < 3
      42
    end

    result.should eq(42)
    attempts.should eq(3)
    recorded_errors.should eq([nil, "boom 1", "boom 2"])
    sleeps.should eq([3.seconds, 6.seconds])
  end

  it "re-raises the last exception after exhausting the retry limit" do
    attempts = 0
    sleeps = [] of Time::Span
    noop_sleeper = ->(span : Time::Span) { sleeps << span }

    expect_raises(Exception, "fail on attempt 4") do
      retry(limit: 3, delay: 1.second, backoff: false, sleeper: noop_sleeper) do |_error, attempt|
        attempts += 1
        raise "fail on attempt #{attempt}"
      end
    end

    attempts.should eq(4)
    sleeps.size.should eq(3)
  end

  it "applies exponential backoff and respects max_delay" do
    sleeps = [] of Time::Span
    noop_sleeper = ->(span : Time::Span) { sleeps << span }

    expect_raises(Exception) do
      retry(
        limit: 4,
        delay: 2.seconds,
        backoff: true,
        jitter: false,
        max_delay: 10.seconds,
        sleeper: noop_sleeper
      ) do
        raise "always fails"
      end
    end

    sleeps.should eq([2.seconds, 4.seconds, 8.seconds, 10.seconds])
  end

  it "applies jitter within the expected bounds when jitter is enabled" do
    sleeps = [] of Time::Span
    noop_sleeper = ->(span : Time::Span) { sleeps << span }
    seeded_random = Random.new(12345)

    expect_raises(Exception) do
      retry(
        limit: 3,
        delay: 4.seconds,
        backoff: false,
        jitter: true,
        random: seeded_random,
        sleeper: noop_sleeper
      ) do
        raise "jitter test"
      end
    end

    sleeps.size.should eq(3)
    sleeps.each do |span|
      span.total_seconds.should be >= 2.0
      span.total_seconds.should be <= 6.0
    end
  end

  it "filters exceptions using only and except" do
    attempts = 0
    noop_sleeper = ->(_span : Time::Span) { nil }

    expect_raises(FatalAuthError) do
      retry(
        limit: 3,
        delay: 1.second,
        only: {Exception},
        except: {FatalAuthError},
        sleeper: noop_sleeper
      ) do
        attempts += 1
        raise FatalAuthError.new("unauthorized")
      end
    end

    attempts.should eq(1)
  end

  it "invokes the on_retry callback before sleeping" do
    events = [] of Tuple(String?, Int32, Time::Span)
    noop_sleeper = ->(_span : Time::Span) { nil }
    callback = ->(ex : Exception, attempt : Int32, wait : Time::Span) do
      events << {ex.message, attempt, wait}
    end

    attempts = 0
    retry(limit: 2, delay: 500.milliseconds, on_retry: callback, sleeper: noop_sleeper) do
      attempts += 1
      raise "transient #{attempts}" if attempts <= 2
      "recovered"
    end

    events.should eq([
      {"transient 1", 1, 500.milliseconds},
      {"transient 2", 2, 500.milliseconds},
    ])
  end

  it "raises ArgumentError when limit or delay is negative" do
    expect_raises(ArgumentError) do
      retry(limit: -1) { "nope" }
    end

    expect_raises(ArgumentError) do
      retry(delay: -1.second) { "nope" }
    end
  end
end
