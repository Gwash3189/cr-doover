require "../spec_helper"

describe Doover::Runner do
  describe "#run" do
    context "when the work succeeds on the first attempt" do
      it "returns the work result" do
        result = Doover.immediate.work { "ok" }.run

        result.should eq("ok")
      end

      it "calls the work function once" do
        calls = 0

        Doover.immediate.work do
          calls += 1
          "ok"
        end.run

        calls.should eq(1)
      end

      it "does not call the sleeper" do
        sleeper = DooverRecordingSleeper.new

        Doover.constant
          .delay(1.second)
          .attempts(3)
          .work { "ok" }
          .sleep_with { |span| sleeper.record(span) }
          .run

        sleeper.sleeps.should be_empty
      end

      it "does not call any handlers" do
        calls = [] of Symbol

        Doover.immediate
          .on_retry { calls << :retry }
          .on_exhausted { calls << :exhausted }
          .work { "ok" }
          .run

        calls.should be_empty
      end
    end

    context "when the work fails before succeeding" do
      it "returns the eventual result" do
        calls = 0

        result = Doover.immediate
          .attempts(3)
          .work do |attempt|
            calls += 1
            raise DooverTransientError.new("transient") if attempt < 3
            :recovered
          end
          .run

        result.should eq(:recovered)
        calls.should eq(3)
      end

      it "does not call exhausted handlers" do
        exhausted = 0

        Doover.immediate
          .attempts(2)
          .work do |attempt|
            raise DooverTransientError.new("transient") if attempt == 1
            attempt
          end
          .on_exhausted { exhausted += 1 }
          .run

        exhausted.should eq(0)
      end

      it "calls the retry handler before sleeping and retrying" do
        calls = [] of Symbol

        result = Doover.constant
          .delay(1.second)
          .attempts(2)
          .work do |attempt|
            calls << :work
            raise DooverTransientError.new("boom") if attempt == 1
            attempt
          end
          .on_retry { calls << :retry }
          .sleep_with { |_span| calls << :sleep }
          .run

        result.should eq(2)
        calls.should eq([:work, :retry, :sleep, :work])
      end
    end

    context "when the work always fails" do
      it "re-raises the original exception object" do
        error = DooverTransientError.new("boom")

        raised = expect_raises(DooverTransientError, "boom") do
          Doover.immediate
            .attempts(3)
            .work { raise error }
            .run
        end

        raised.should be(error)
      end

      it "calls work exactly the configured number of total attempts" do
        attempts = [] of Int32

        expect_raises(DooverTransientError) do
          Doover.immediate
            .attempts(3)
            .work do |attempt|
              attempts << attempt
              raise DooverTransientError.new("boom")
            end
            .run
        end

        attempts.should eq([1, 2, 3])
      end

      it "does not call retry handlers on the final attempt" do
        attempts = [] of Int32

        expect_raises(DooverTransientError) do
          Doover.immediate
            .attempts(3)
            .work { raise DooverTransientError.new("boom") }
            .on_retry { |_error, attempt| attempts << attempt }
            .run
        end

        attempts.should eq([1, 2])
      end

      it "calls exhausted handlers with the final error and total attempt count" do
        received : Tuple(String?, Int32)? = nil

        expect_raises(DooverTransientError, "boom 3") do
          Doover.immediate
            .attempts(3)
            .work { |attempt| raise DooverTransientError.new("boom #{attempt}") }
            .on_exhausted { |error, attempts| received = {error.message, attempts} }
            .run
        end

        received.should eq({"boom 3", 3})
      end

      it "runs every exhausted handler in registration order" do
        calls = [] of Symbol

        expect_raises(DooverTransientError) do
          Doover.immediate
            .attempts(1)
            .work { raise DooverTransientError.new("boom") }
            .on_exhausted { calls << :first }
            .on_exhausted { calls << :second }
            .run
        end

        calls.should eq([:first, :second])
      end

      it "re-raises the original exception object after running exhausted handlers" do
        error = DooverTransientError.new("boom")
        exhausted_error : Exception? = nil

        raised = expect_raises(DooverTransientError, "boom") do
          Doover.immediate
            .attempts(2)
            .work { raise error }
            .on_exhausted { |final_error, _attempts| exhausted_error = final_error }
            .run
        end

        exhausted_error.should be(error)
        raised.should be(error)
      end

      it "does not call retry handlers when only one attempt is allowed" do
        retry_calls = 0
        exhausted_calls = 0

        expect_raises(DooverTransientError) do
          Doover.immediate
            .attempts(1)
            .work { raise DooverTransientError.new("boom") }
            .on_retry { retry_calls += 1 }
            .on_exhausted { exhausted_calls += 1 }
            .run
        end

        retry_calls.should eq(0)
        exhausted_calls.should eq(1)
      end
    end

    context "with exponential backoff" do
      it "sleeps base * 2^(attempt - 1)" do
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

    context "with linear backoff" do
      it "sleeps base * attempt" do
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

    context "with constant backoff" do
      it "sleeps the base delay on every retry" do
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

    context "with immediate retries" do
      it "never calls the sleeper" do
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

    context "with a zero delay" do
      it "never calls the sleeper" do
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

      it "never calls the sleeper when max_delay caps the delay to zero" do
        sleeper = DooverRecordingSleeper.new

        expect_raises(DooverTransientError) do
          Doover.constant
            .delay(1.second)
            .max_delay(Time::Span.zero)
            .attempts(3)
            .work { raise DooverTransientError.new("boom") }
            .sleep_with { |span| sleeper.record(span) }
            .run
        end

        sleeper.sleeps.should be_empty
      end
    end

    context "with retry handlers" do
      it "receives the failed attempt's error and attempt number" do
        received = [] of Tuple(String?, Int32)

        result = Doover.immediate
          .attempts(3)
          .work do |attempt|
            raise DooverTransientError.new("boom #{attempt}") if attempt == 1
            attempt
          end
          .on_retry { |error, attempt| received << {error.message, attempt} }
          .run

        result.should eq(2)
        received.should eq([{"boom 1", 1}])
      end

      it "aborts immediately when a handler returns false" do
        calls = 0

        raised = expect_raises(DooverFatalError, "fatal") do
          Doover.immediate
            .attempts(5)
            .work do
              calls += 1
              raise DooverFatalError.new("fatal")
            end
            .on_retry { |_error, _attempt| false }
            .run
        end

        raised.message.should eq("fatal")
        calls.should eq(1)
      end

      it "does not call exhausted handlers when aborted" do
        exhausted = 0

        expect_raises(DooverFatalError) do
          Doover.immediate
            .attempts(5)
            .work { raise DooverFatalError.new("fatal") }
            .on_retry { |_error, _attempt| false }
            .on_exhausted { exhausted += 1 }
            .run
        end

        exhausted.should eq(0)
      end

      it "does not sleep when aborted" do
        sleeper = DooverRecordingSleeper.new

        expect_raises(DooverTransientError) do
          Doover.constant
            .delay(1.second)
            .attempts(5)
            .work { raise DooverTransientError.new("boom") }
            .on_retry { |_error, _attempt| false }
            .sleep_with { |span| sleeper.record(span) }
            .run
        end

        sleeper.sleeps.should be_empty
      end

      it "continues when a handler returns true" do
        result = Doover.immediate
          .attempts(2)
          .work do |attempt|
            raise DooverTransientError.new("boom") if attempt == 1
            attempt
          end
          .on_retry { |_error, _attempt| true }
          .run

        result.should eq(2)
      end

      it "continues when a handler returns nil" do
        result = Doover.immediate
          .attempts(2)
          .work do |attempt|
            raise DooverTransientError.new("boom") if attempt == 1
            attempt
          end
          .on_retry { |_error, _attempt| nil }
          .run

        result.should eq(2)
      end

      it "continues when a handler returns a non-boolean value" do
        result = Doover.immediate
          .attempts(2)
          .work do |attempt|
            raise DooverTransientError.new("boom") if attempt == 1
            attempt
          end
          .on_retry { |_error, _attempt| "keep going" }
          .run

        result.should eq(2)
      end

      it "continues when a handler returns zero" do
        result = Doover.immediate
          .attempts(2)
          .work do |attempt|
            raise DooverTransientError.new("boom") if attempt == 1
            attempt
          end
          .on_retry { |_error, _attempt| 0 }
          .run

        result.should eq(2)
      end

      it "runs handlers in registration order" do
        calls = [] of Symbol

        Doover.immediate
          .attempts(2)
          .work do |attempt|
            raise DooverTransientError.new("boom") if attempt == 1
            attempt
          end
          .on_retry { calls << :first; true }
          .on_retry { calls << :second; true }
          .run

        calls.should eq([:first, :second])
      end

      it "stops running handlers after one returns false" do
        calls = [] of Symbol

        expect_raises(DooverTransientError) do
          Doover.immediate
            .attempts(2)
            .work { raise DooverTransientError.new("boom") }
            .on_retry { calls << :first; true }
            .on_retry { calls << :second; false }
            .on_retry { calls << :third; true }
            .run
        end

        calls.should eq([:first, :second])
      end
    end

    context "with handlers registered before and after #work" do
      it "runs retry handlers from both sides" do
        calls = [] of Symbol

        result = Doover.immediate
          .on_retry { calls << :before_work; true }
          .work do |attempt|
            raise DooverTransientError.new("boom") if attempt == 1
            attempt
          end
          .on_retry { calls << :after_work; true }
          .run

        result.should eq(2)
        calls.should eq([:before_work, :after_work])
      end

      it "runs exhausted handlers from both sides" do
        calls = [] of Symbol

        expect_raises(DooverTransientError) do
          Doover.immediate
            .on_exhausted { calls << :before_work }
            .work { raise DooverTransientError.new("boom") }
            .on_exhausted { calls << :after_work }
            .attempts(1)
            .run
        end

        calls.should eq([:before_work, :after_work])
      end
    end

    context "with jitter" do
      it "scales the delay by the random fraction" do
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

      it "keeps delays within zero and the calculated delay" do
        sleeper = DooverRecordingSleeper.new

        expect_raises(DooverTransientError) do
          Doover.exponential
            .delay(1.second)
            .jitter
            .random(Random.new(1234))
            .attempts(3)
            .work { raise DooverTransientError.new("boom") }
            .sleep_with { |span| sleeper.record(span) }
            .run
        end

        sleeper.sleeps.size.should eq(2)
        sleeper.sleeps[0].should be >= Time::Span.zero
        sleeper.sleeps[0].should be <= 1.second
        sleeper.sleeps[1].should be >= Time::Span.zero
        sleeper.sleeps[1].should be <= 2.seconds
      end

      it "does not call the sleeper when jitter produces a zero delay" do
        sleeper = DooverRecordingSleeper.new
        random = DooverFixedRandom.new(0.0)

        expect_raises(DooverTransientError) do
          Doover.constant
            .delay(1.second)
            .jitter
            .random(random)
            .attempts(2)
            .work { raise DooverTransientError.new("boom") }
            .sleep_with { |span| sleeper.record(span) }
            .run
        end

        random.calls.should eq(1)
        sleeper.sleeps.should be_empty
      end
    end

    context "with a maximum delay" do
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

      it "caps the delay before applying jitter" do
        sleeper = DooverRecordingSleeper.new

        expect_raises(DooverTransientError) do
          Doover.constant
            .delay(1.second)
            .max_delay(400.milliseconds)
            .jitter
            .random(DooverFixedRandom.new(0.5))
            .attempts(2)
            .work { raise DooverTransientError.new("boom") }
            .sleep_with { |span| sleeper.record(span) }
            .run
        end

        sleeper.sleeps.should eq([200.milliseconds])
      end

      it "does not sleep after the final failed attempt" do
        sleeper = DooverRecordingSleeper.new

        expect_raises(DooverTransientError) do
          Doover.constant
            .delay(1.second)
            .attempts(3)
            .work { raise DooverTransientError.new("boom") }
            .sleep_with { |span| sleeper.record(span) }
            .run
        end

        sleeper.sleeps.should eq([1.second, 1.second])
      end
    end

    context "when reused" do
      it "starts again at attempt 1 on every run" do
        attempts = [] of Int32

        runner = Doover.immediate.work do |attempt|
          attempts << attempt
          raise DooverTransientError.new("boom") if attempt == 1
          attempt
        end

        runner.run.should eq(2)
        runner.run.should eq(2)
        attempts.should eq([1, 2, 1, 2])
      end

      it "keeps configuration changes on a runner independent" do
        base = Doover.constant
          .delay(1.second)
          .work { raise DooverTransientError.new("boom") }
        branch = base.attempts(1)
        base_sleeper = DooverRecordingSleeper.new
        branch_sleeper = DooverRecordingSleeper.new

        expect_raises(DooverTransientError) do
          base.sleep_with { |span| base_sleeper.record(span) }.run
        end

        expect_raises(DooverTransientError) do
          branch.sleep_with { |span| branch_sleeper.record(span) }.run
        end

        base_sleeper.sleeps.should eq([1.second, 1.second])
        branch_sleeper.sleeps.should be_empty
      end
    end

    context "with different result types" do
      it "preserves String results" do
        result = Doover.immediate.work { "ok" }.run

        result.should eq("ok")
        typeof(result).should eq(String)
      end

      it "preserves Int32 results" do
        result = Doover.immediate.work { 42 }.run

        result.should eq(42)
        typeof(result).should eq(Int32)
      end

      it "preserves Nil results" do
        result = Doover.immediate.work { nil }.run

        result.should be_nil
        typeof(result).should eq(Nil)
      end
    end
  end
end
