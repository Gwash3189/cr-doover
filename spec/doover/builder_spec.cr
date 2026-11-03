require "../spec_helper"

describe Doover do
  describe ".exponential" do
    it "builds a builder with the exponential strategy" do
      Doover.exponential.config.strategy.should eq(Doover::Strategy::Exponential)
    end
  end

  describe ".linear" do
    it "builds a builder with the linear strategy" do
      Doover.linear.config.strategy.should eq(Doover::Strategy::Linear)
    end
  end

  describe ".constant" do
    it "builds a builder with the constant strategy" do
      Doover.constant.config.strategy.should eq(Doover::Strategy::Constant)
    end
  end

  describe ".immediate" do
    it "builds a builder with the immediate strategy" do
      Doover.immediate.config.strategy.should eq(Doover::Strategy::Immediate)
    end
  end

  describe "defaults" do
    it "uses the exponential strategy" do
      Doover::Config.new.strategy.should eq(Doover::Strategy::Exponential)
    end

    it "uses three total attempts" do
      Doover.exponential.config.attempts.should eq(3)
    end

    it "uses a 100 millisecond base delay" do
      Doover.exponential.config.base_delay.should eq(100.milliseconds)
    end

    it "disables jitter" do
      Doover.exponential.config.jitter.should be_false
    end

    it "has no maximum delay" do
      Doover.exponential.config.max_delay.should be_nil
    end
  end

  describe "#attempts" do
    it "sets the total number of attempts" do
      Doover.exponential.attempts(5).config.attempts.should eq(5)
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
    it "sets the base delay" do
      Doover.exponential.delay(250.milliseconds).config.base_delay.should eq(250.milliseconds)
    end

    it "raises for a negative delay" do
      expect_raises(ArgumentError) do
        Doover.exponential.delay(-1.millisecond)
      end
    end
  end

  describe "#jitter" do
    it "enables jitter by default" do
      Doover.exponential.jitter.config.jitter.should be_true
    end

    it "can explicitly disable jitter" do
      Doover.exponential.jitter(false).config.jitter.should be_false
    end
  end

  describe "#max_delay" do
    it "sets the maximum delay" do
      Doover.exponential.max_delay(2.seconds).config.max_delay.should eq(2.seconds)
    end

    it "raises for a negative maximum delay" do
      expect_raises(ArgumentError) do
        Doover.exponential.max_delay(-1.millisecond)
      end
    end
  end

  describe "#random" do
    it "sets the random source" do
      source = DooverFixedRandom.new(0.5)
      Doover.exponential.random(source).config.random.next_float.should eq(0.5)
    end
  end

  describe "#sleep_with" do
    it "returns a builder" do
      builder = Doover.exponential.sleep_with { |_span| nil }
      builder.should be_a(Doover::Builder)
    end
  end

  describe "#work" do
    it "returns a typed runner" do
      runner = Doover.exponential.work { |attempt| attempt }
      runner.should be_a(Doover::Runner(Int32))
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
    it "does not mutate the original builder" do
      builder = Doover.constant
      builder.attempts(5)
      builder.config.attempts.should eq(3)
    end

    it "keeps independent branches separate" do
      builder = Doover.constant
      first = builder.attempts(5)
      second = builder.attempts(2)

      first.config.attempts.should eq(5)
      second.config.attempts.should eq(2)
    end

    it "does not share retry handler storage between branches" do
      builder = Doover.immediate
      with_handler = builder.on_retry { true }

      builder.config.retry_handlers.size.should eq(0)
      with_handler.config.retry_handlers.size.should eq(1)
    end

    it "does not mutate earlier handlers when adding another" do
      first = Doover.immediate.on_retry { true }
      second = first.on_retry { true }

      first.config.retry_handlers.size.should eq(1)
      second.config.retry_handlers.size.should eq(2)
    end
  end
end
