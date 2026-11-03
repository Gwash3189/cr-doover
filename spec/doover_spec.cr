require "./spec_helper"

describe Doover do
  describe "::VERSION" do
    it "exposes the shard version" do
      Doover::VERSION.should eq("0.2.0")
    end
  end
end
