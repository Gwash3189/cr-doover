require "../spec_helper"

class MacroRetryService
  include Doover

  getter attempts = [] of Int32
  getter sleeps = [] of Time::Span
  getter retry_events = [] of Tuple(String?, Int32)
  getter exhausted_events = [] of Tuple(String?, Int32)

  do_over method: :perform,
    strategy: :exponential,
    attempts: 3,
    delay: 100.milliseconds,
    on_retry: :handle_retry,
    on_exhausted: :handle_exhausted,
    sleeper: :record_sleep

  def perform(failures : Int32) : String
    @attempts << @attempts.size + 1
    raise DooverTransientError.new("boom #{@attempts.size}") if @attempts.size <= failures
    "ok"
  end

  private def handle_retry(error : Exception, attempt : Int32) : Bool
    @retry_events << {error.message, attempt}
    true
  end

  private def handle_exhausted(error : Exception, attempts : Int32) : Nil
    @exhausted_events << {error.message, attempts}
  end

  private def record_sleep(span : Time::Span) : Nil
    @sleeps << span
  end
end

class MacroAbortService
  include Doover

  getter retry_count = 0
  getter exhausted_count = 0
  getter sleeps = [] of Time::Span

  do_over method: :perform,
    strategy: :constant,
    attempts: 3,
    delay: 10.milliseconds,
    on_retry: :handle_retry,
    on_exhausted: :handle_exhausted,
    sleeper: :record_sleep

  def perform : String
    raise DooverFatalError.new("fatal")
  end

  private def handle_retry(error : Exception, attempt : Int32) : Bool
    @retry_count += 1
    false
  end

  private def handle_exhausted(error : Exception, attempts : Int32) : Nil
    @exhausted_count += 1
  end

  private def record_sleep(span : Time::Span) : Nil
    @sleeps << span
  end
end

class MacroJitterService
  include Doover

  getter sleeps = [] of Time::Span

  do_over method: :perform,
    strategy: :constant,
    attempts: 2,
    delay: 100.milliseconds,
    jitter: true,
    random: :random_source,
    sleeper: :record_sleep

  def perform : String
    raise DooverTransientError.new("boom")
  end

  private def random_source : Random
    DooverFixedRandom.new(0.25)
  end

  private def record_sleep(span : Time::Span) : Nil
    @sleeps << span
  end
end

class MacroMaxDelayService
  include Doover

  getter sleeps = [] of Time::Span

  do_over method: :perform,
    strategy: :exponential,
    attempts: 4,
    delay: 100.milliseconds,
    max_delay: 150.milliseconds,
    sleeper: :record_sleep

  def perform : String
    raise DooverTransientError.new("boom")
  end

  private def record_sleep(span : Time::Span) : Nil
    @sleeps << span
  end
end

class MacroLinearService
  include Doover

  getter sleeps = [] of Time::Span

  do_over method: :perform,
    strategy: :linear,
    attempts: 3,
    delay: 10.milliseconds,
    sleeper: :record_sleep

  def perform : String
    raise DooverTransientError.new("boom")
  end

  private def record_sleep(span : Time::Span) : Nil
    @sleeps << span
  end
end

class MacroForwardingService
  include Doover

  do_over method: :basic, strategy: :immediate
  do_over method: :with_default, strategy: :immediate
  do_over method: :with_splat, strategy: :immediate
  do_over method: :with_options, strategy: :immediate
  do_over method: :with_typed_options, strategy: :immediate
  do_over method: :with_all, strategy: :immediate
  do_over method: :with_named, strategy: :immediate
  do_over method: :with_external_name, strategy: :immediate
  do_over method: :with_yield, strategy: :immediate
  do_over method: :with_block, strategy: :immediate
  do_over method: :with_default_and_block, strategy: :immediate
  do_over method: :question?, strategy: :immediate
  do_over method: :secret, strategy: :immediate
  do_over method: :protected_secret, strategy: :immediate
  do_over method: :overloaded, strategy: :immediate
  do_over method: :nil_result, strategy: :immediate
  do_over method: :no_args, strategy: :immediate

  def basic(value : Int32) : Int32
    value + 1
  end

  def with_default(value : Int32, prefix : String = "v") : String
    "#{prefix}#{value}"
  end

  def with_splat(value : Int32, *rest : String) : String
    "#{value}:#{rest.join(",")}"
  end

  def with_options(value : Int32, **options) : String
    "#{value}:#{options.size}"
  end

  def with_typed_options(**options : Int32) : Int32
    options.size
  end

  def with_all(value : Int32, *rest : String, suffix : String = "!", **options) : String
    "#{value}-#{rest.join(",")}-#{suffix}-#{options.size}"
  end

  def with_named(value : Int32, *, flag : Bool = false) : String
    "#{value}:#{flag}"
  end

  def with_external_name(to value : Int32) : String
    "#{value}:#{value}"
  end

  def with_yield(value : Int32, &) : String
    yield value
  end

  def with_block(value : Int32, &block : Int32 -> String) : String
    block.call(value)
  end

  def with_default_and_block(value : Int32, prefix : String = "v", &block : Int32 -> String) : String
    "#{prefix}#{block.call(value)}"
  end

  def question?(value : Int32) : Bool
    value > 0
  end

  private def secret : String
    "secret"
  end

  def call_secret : String
    secret
  end

  protected def protected_secret : String
    "protected"
  end

  def call_protected_secret : String
    protected_secret
  end

  def overloaded(value : Int32) : String
    "int:#{value}"
  end

  def overloaded(value : String) : String
    "str:#{value}"
  end

  def nil_result : Nil
    nil
  end

  def no_args : String
    "no args"
  end
end

class MacroAfterService
  include Doover

  def perform(value : Int32) : Int32
    value * 2
  end

  do_over method: :perform, strategy: :immediate
end

class MacroPositionalService
  include Doover

  do_over :perform, strategy: :immediate

  def perform : String
    "positional"
  end
end

describe "do_over macro" do
  describe "retrying an instance method" do
    context "when the method eventually succeeds" do
      it "returns the method result" do
        MacroRetryService.new.perform(2).should eq("ok")
      end

      it "retries with 1-indexed attempt numbers" do
        service = MacroRetryService.new

        service.perform(2)

        service.attempts.should eq([1, 2, 3])
      end

      it "uses the configured backoff" do
        service = MacroRetryService.new

        service.perform(2)

        service.sleeps.should eq([100.milliseconds, 200.milliseconds])
      end

      it "calls on_retry with the failure and attempt number" do
        service = MacroRetryService.new

        service.perform(2)

        service.retry_events.should eq([{"boom 1", 1}, {"boom 2", 2}])
      end

      it "does not call on_exhausted" do
        service = MacroRetryService.new

        service.perform(2)

        service.exhausted_events.should be_empty
      end
    end

    context "when the method always fails" do
      it "raises the final error" do
        service = MacroRetryService.new

        expect_raises(DooverTransientError, "boom 3") do
          service.perform(3)
        end
      end

      it "calls on_exhausted with the final error and attempt count" do
        service = MacroRetryService.new

        expect_raises(DooverTransientError) do
          service.perform(3)
        end

        service.exhausted_events.should eq([{"boom 3", 3}])
      end

      it "sleeps between attempts" do
        service = MacroRetryService.new

        expect_raises(DooverTransientError) do
          service.perform(3)
        end

        service.sleeps.should eq([100.milliseconds, 200.milliseconds])
      end
    end
  end

  describe "aborting from on_retry" do
    it "raises the original error" do
      service = MacroAbortService.new

      expect_raises(DooverFatalError, "fatal") do
        service.perform
      end
    end

    it "does not sleep" do
      service = MacroAbortService.new

      expect_raises(DooverFatalError) { service.perform }

      service.sleeps.should be_empty
    end

    it "does not call on_exhausted" do
      service = MacroAbortService.new

      expect_raises(DooverFatalError) { service.perform }

      service.exhausted_count.should eq(0)
    end

    it "calls on_retry once" do
      service = MacroAbortService.new

      expect_raises(DooverFatalError) { service.perform }

      service.retry_count.should eq(1)
    end
  end

  describe "jitter" do
    it "uses the configured random source" do
      service = MacroJitterService.new

      expect_raises(DooverTransientError) { service.perform }

      service.sleeps.should eq([25.milliseconds])
    end
  end

  describe "max_delay" do
    it "caps the calculated delay" do
      service = MacroMaxDelayService.new

      expect_raises(DooverTransientError) { service.perform }

      service.sleeps.should eq([100.milliseconds, 150.milliseconds, 150.milliseconds])
    end
  end

  describe "linear strategy" do
    it "scales the delay by attempt" do
      service = MacroLinearService.new

      expect_raises(DooverTransientError) { service.perform }

      service.sleeps.should eq([10.milliseconds, 20.milliseconds])
    end
  end

  describe "method forwarding" do
    it "forwards a basic argument" do
      MacroForwardingService.new.basic(1).should eq(2)
    end

    it "forwards default arguments" do
      MacroForwardingService.new.with_default(2).should eq("v2")
    end

    it "forwards named arguments" do
      MacroForwardingService.new.with_default(2, prefix: "n").should eq("n2")
    end

    it "forwards splat arguments" do
      MacroForwardingService.new.with_splat(1, "a", "b").should eq("1:a,b")
    end

    it "forwards double-splat arguments" do
      MacroForwardingService.new.with_options(1, a: 1, b: 2).should eq("1:2")
    end

    it "forwards typed double-splat arguments" do
      MacroForwardingService.new.with_typed_options(a: 1, b: 2).should eq(2)
    end

    it "forwards splat, named-only, and double-splat arguments together" do
      MacroForwardingService.new.with_all(1, "a", "b", suffix: "?", x: 1).should eq("1-a,b-?-1")
    end

    it "forwards named-only arguments" do
      MacroForwardingService.new.with_named(1, flag: true).should eq("1:true")
    end

    it "forwards external argument names" do
      MacroForwardingService.new.with_external_name(to: 3).should eq("3:3")
    end

    it "forwards yield-based blocks" do
      MacroForwardingService.new.with_yield(3) { |value| (value * 2).to_s }.should eq("6")
    end

    it "forwards typed captured blocks" do
      MacroForwardingService.new.with_block(3) { |value| "<#{value}>" }.should eq("<3>")
    end

    it "forwards default arguments with typed captured blocks" do
      MacroForwardingService.new.with_default_and_block(3) { |value| value.to_s }.should eq("v3")
    end

    it "forwards predicate method names" do
      MacroForwardingService.new.question?(1).should be_true
    end

    it "preserves private visibility" do
      MacroForwardingService.new.call_secret.should eq("secret")
    end

    it "preserves protected visibility" do
      MacroForwardingService.new.call_protected_secret.should eq("protected")
    end

    it "forwards overloaded methods" do
      service = MacroForwardingService.new

      service.overloaded(1).should eq("int:1")
      service.overloaded("x").should eq("str:x")
    end

    it "forwards nil results" do
      MacroForwardingService.new.nil_result.should be_nil
    end

    it "forwards methods without arguments" do
      MacroForwardingService.new.no_args.should eq("no args")
    end
  end

  describe "declaration placement" do
    it "wraps a method when do_over appears after it" do
      MacroAfterService.new.perform(3).should eq(6)
    end

    it "accepts a positional method name" do
      MacroPositionalService.new.perform.should eq("positional")
    end
  end
end
