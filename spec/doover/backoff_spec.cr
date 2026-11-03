require "../spec_helper"

describe Doover::Backoff do
  describe ".compute" do
    context "with an immediate strategy" do
      it "returns zero" do
        Doover::Backoff
          .compute(Doover::Strategy::Immediate, 1.second, 1)
          .should eq(Time::Span.zero)
      end
    end

    context "when the base delay is not positive" do
      it "returns zero for every strategy" do
        strategies = [
          Doover::Strategy::Exponential,
          Doover::Strategy::Linear,
          Doover::Strategy::Constant,
        ]

        strategies.each do |strategy|
          Doover::Backoff.compute(strategy, Time::Span.zero, 3).should eq(Time::Span.zero)
          Doover::Backoff.compute(strategy, -1.second, 3).should eq(Time::Span.zero)
        end
      end
    end

    context "with the exponential strategy" do
      it "doubles the base delay for each attempt" do
        delays = (1..3).map do |attempt|
          Doover::Backoff.compute(Doover::Strategy::Exponential, 100.milliseconds, attempt)
        end

        delays.should eq([100.milliseconds, 200.milliseconds, 400.milliseconds])
      end
    end

    context "with the linear strategy" do
      it "multiplies the base delay by the attempt number" do
        delays = (1..3).map do |attempt|
          Doover::Backoff.compute(Doover::Strategy::Linear, 100.milliseconds, attempt)
        end

        delays.should eq([100.milliseconds, 200.milliseconds, 300.milliseconds])
      end
    end

    context "with the constant strategy" do
      it "returns the base delay for every attempt" do
        delays = (1..3).map do |attempt|
          Doover::Backoff.compute(Doover::Strategy::Constant, 100.milliseconds, attempt)
        end

        delays.should eq([100.milliseconds, 100.milliseconds, 100.milliseconds])
      end
    end

    context "when a maximum delay is configured" do
      it "clamps the calculated delay" do
        delays = (1..4).map do |attempt|
          Doover::Backoff.compute(
            Doover::Strategy::Exponential,
            1.second,
            attempt,
            max_delay: 3.seconds
          )
        end

        delays.should eq([1.second, 2.seconds, 3.seconds, 3.seconds])
      end
    end

    context "with jitter enabled" do
      it "returns a fraction of the calculated delay" do
        Doover::Backoff
          .compute(
            Doover::Strategy::Constant,
            1.second,
            1,
            jitter: true,
            random: DooverFixedRandom.new(0.25)
          )
          .should eq(250.milliseconds)
      end

      it "can produce a zero delay" do
        Doover::Backoff
          .compute(
            Doover::Strategy::Constant,
            1.second,
            1,
            jitter: true,
            random: DooverFixedRandom.new(0.0)
          )
          .should eq(Time::Span.zero)
      end

      it "samples below half of the calculated delay" do
        Doover::Backoff
          .compute(
            Doover::Strategy::Constant,
            1.second,
            1,
            jitter: true,
            random: DooverFixedRandom.new(0.1)
          )
          .should eq(100.milliseconds)
      end

      it "stays within the calculated delay for a seeded random source" do
        random = Random.new(1234)
        upper_bounds = [1.second, 2.seconds, 4.seconds]

        upper_bounds.each_with_index do |upper_bound, index|
          delay = Doover::Backoff.compute(
            Doover::Strategy::Exponential,
            1.second,
            index + 1,
            jitter: true,
            random: random
          )

          delay.should be >= Time::Span.zero
          delay.should be <= upper_bound
        end
      end

      it "applies jitter after the maximum delay cap" do
        Doover::Backoff
          .compute(
            Doover::Strategy::Constant,
            1.second,
            1,
            jitter: true,
            max_delay: 400.milliseconds,
            random: DooverFixedRandom.new(0.5)
          )
          .should eq(200.milliseconds)
      end
    end

    context "with extreme exponential attempts" do
      it "saturates at Time::Span::MAX" do
        Doover::Backoff
          .compute(Doover::Strategy::Exponential, 1.second, 100)
          .should eq(Time::Span::MAX)
      end

      it "saturates at the configured maximum delay" do
        Doover::Backoff
          .compute(Doover::Strategy::Exponential, 1.second, 100, max_delay: 5.seconds)
          .should eq(5.seconds)
      end

      it "does not raise OverflowError for the largest attempt number" do
        Doover::Backoff
          .compute(Doover::Strategy::Exponential, 1.second, Int32::MAX)
          .should eq(Time::Span::MAX)
      end
    end

    context "with extreme linear attempts" do
      it "saturates at Time::Span::MAX" do
        Doover::Backoff
          .compute(Doover::Strategy::Linear, Time::Span::MAX, 2)
          .should eq(Time::Span::MAX)
      end
    end
  end
end
