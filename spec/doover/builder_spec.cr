require "../spec_helper"

describe Doover::Builder do
  describe ".exponential" do
    it "retries with exponentially increasing delays" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.exponential
          .delay(100.milliseconds)
          .attempts(4)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([100.milliseconds, 200.milliseconds, 400.milliseconds])
    end
  end

  describe ".linear" do
    it "retries with linearly increasing delays" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.linear
          .delay(100.milliseconds)
          .attempts(4)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([100.milliseconds, 200.milliseconds, 300.milliseconds])
    end
  end

  describe ".constant" do
    it "retries with the same delay every time" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.constant
          .delay(100.milliseconds)
          .attempts(4)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([100.milliseconds, 100.milliseconds, 100.milliseconds])
    end
  end

  describe ".immediate" do
    it "retries without sleeping" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.immediate
          .attempts(3)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should be_empty
    end
  end

  describe "defaults" do
    it "uses exponential backoff" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.exponential
          .attempts(4)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([100.milliseconds, 200.milliseconds, 400.milliseconds])
    end

    it "uses three total attempts" do
      calls = 0

      expect_raises(DooverTransientError) do
        Doover.exponential
          .work do
            calls += 1
            raise DooverTransientError.new("boom")
          end
          .sleep_with { |_span| }
          .run
      end

      calls.should eq(3)
    end

    it "uses a 100 millisecond base delay" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.exponential
          .attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([100.milliseconds])
    end
  end

  describe "#attempts" do
    it "uses the configured total number of attempts" do
      calls = 0

      expect_raises(DooverTransientError) do
        Doover.immediate
          .attempts(5)
          .work do
            calls += 1
            raise DooverTransientError.new("boom")
          end
          .run
      end

      calls.should eq(5)
    end

    it "accepts a single attempt" do
      calls = 0

      expect_raises(DooverTransientError) do
        Doover.immediate
          .attempts(1)
          .work do
            calls += 1
            raise DooverTransientError.new("boom")
          end
          .run
      end

      calls.should eq(1)
    end

    it "raises when fewer than one attempt is requested" do
      expect_raises(ArgumentError) do
        Doover.exponential.attempts(0)
      end
    end

    it "raises for a negative attempt count" do
      expect_raises(ArgumentError) do
        Doover.exponential.attempts(-1)
      end
    end
  end

  describe "#delay" do
    it "uses the configured base delay" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.constant
          .delay(250.milliseconds)
          .attempts(3)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([250.milliseconds, 250.milliseconds])
    end

    it "accepts a zero delay without sleeping" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.constant
          .delay(Time::Span.zero)
          .attempts(3)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should be_empty
    end

    it "raises for a negative delay" do
      expect_raises(ArgumentError) do
        Doover.exponential.delay(-1.millisecond)
      end
    end
  end

  describe "#jitter" do
    it "enables full jitter" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.constant
          .delay(1.second)
          .jitter
          .random(DooverFixedRandom.new(0.25))
          .attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([250.milliseconds])
    end

    it "can explicitly disable jitter" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.constant
          .delay(1.second)
          .jitter(false)
          .random(DooverFixedRandom.new(0.25))
          .attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([1.second])
    end
  end

  describe "#max_delay" do
    it "caps the calculated delay" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.exponential
          .delay(1.second)
          .max_delay(3.seconds)
          .attempts(4)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([1.second, 2.seconds, 3.seconds])
    end

    it "accepts a zero maximum delay without sleeping" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.constant
          .delay(1.second)
          .max_delay(Time::Span.zero)
          .attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should be_empty
    end

    it "raises for a negative maximum delay" do
      expect_raises(ArgumentError) do
        Doover.exponential.max_delay(-1.millisecond)
      end
    end
  end

  describe "#random" do
    it "uses the configured random source for jitter" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.constant
          .delay(1.second)
          .jitter
          .random(DooverFixedRandom.new(0.75))
          .attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([750.milliseconds])
    end
  end

  describe "#sleep_with" do
    it "uses the provided sleeper between attempts" do
      sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        Doover.constant
          .delay(1.second)
          .attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| sleeper.record(span) }
          .run
      end

      sleeper.sleeps.should eq([1.second])
    end
  end

  describe "#work" do
    it "returns a runner typed by the work result" do
      runner = Doover.immediate.work { "ok" }

      runner.should be_a(Doover::Runner(String))
    end

    it "captures the work block for later execution" do
      Doover.immediate.work { "ok" }.run.should eq("ok")
    end
  end

  describe "#run" do
    context "when no work function is provided" do
      it "raises ArgumentError with a clear message" do
        expect_raises(ArgumentError, "No work function provided. Call #work before #run.") do
          Doover.exponential.run
        end
      end
    end
  end

  describe "configuration branching" do
    it "does not leak attempt changes to the original builder" do
      base = Doover.immediate
      branch = base.attempts(1)
      base_calls = 0
      branch_calls = 0

      expect_raises(DooverTransientError) do
        base.work do
          base_calls += 1
          raise DooverTransientError.new("boom")
        end.run
      end

      expect_raises(DooverTransientError) do
        branch.work do
          branch_calls += 1
          raise DooverTransientError.new("boom")
        end.run
      end

      base_calls.should eq(3)
      branch_calls.should eq(1)
    end

    it "does not leak delay changes to the original builder" do
      base = Doover.constant.delay(1.second)
      branch = base.delay(2.seconds)
      base_sleeper = DooverRecordingSleeper.new
      branch_sleeper = DooverRecordingSleeper.new

      expect_raises(DooverTransientError) do
        base.attempts(3)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| base_sleeper.record(span) }
          .run
      end

      expect_raises(DooverTransientError) do
        branch.attempts(3)
          .work { raise DooverTransientError.new("boom") }
          .sleep_with { |span| branch_sleeper.record(span) }
          .run
      end

      base_sleeper.sleeps.should eq([1.second, 1.second])
      branch_sleeper.sleeps.should eq([2.seconds, 2.seconds])
    end

    it "does not leak retry handlers into the original builder" do
      base = Doover.immediate
      calls = 0
      branch = base.on_retry do
        calls += 1
        true
      end

      expect_raises(DooverTransientError) do
        base.attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .run
      end

      calls.should eq(0)

      expect_raises(DooverTransientError) do
        branch.attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .run
      end

      calls.should eq(1)
    end

    it "does not leak exhausted handlers into the original builder" do
      base = Doover.immediate
      calls = 0
      branch = base.on_exhausted { calls += 1 }

      expect_raises(DooverTransientError) do
        base.attempts(1)
          .work { raise DooverTransientError.new("boom") }
          .run
      end

      calls.should eq(0)

      expect_raises(DooverTransientError) do
        branch.attempts(1)
          .work { raise DooverTransientError.new("boom") }
          .run
      end

      calls.should eq(1)
    end

    it "does not mutate earlier handler registrations when adding another" do
      first_calls = 0
      second_calls = 0
      first = Doover.immediate.on_retry do
        first_calls += 1
        true
      end
      second = first.on_retry do
        second_calls += 1
        true
      end

      expect_raises(DooverTransientError) do
        first.attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .run
      end

      first_calls.should eq(1)
      second_calls.should eq(0)

      expect_raises(DooverTransientError) do
        second.attempts(2)
          .work { raise DooverTransientError.new("boom") }
          .run
      end

      first_calls.should eq(2)
      second_calls.should eq(1)
    end
  end
end
