require "./spec_helper"

describe Doover do
  describe "::VERSION" do
    it "exposes the shard version" do
      Doover::VERSION.should eq("0.3.0")
    end
  end

  describe "removed legacy APIs" do
    it "does not expose the old top-level retry API" do
      Doover.responds_to?(:retry).should be_false
    end

    it "does not expose only or except configuration" do
      builder = Doover.exponential

      builder.responds_to?(:only).should be_false
      builder.responds_to?(:except).should be_false
    end
  end
end
