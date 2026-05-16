# frozen_string_literal: true

RSpec.describe Findbug do
  it "has a version number" do
    expect(Findbug::VERSION).not_to be nil
  end

  it "exposes a Configuration object via .config" do
    expect(Findbug.config).to be_a(Findbug::Configuration)
  end

  it "loads the AdapterHelper module" do
    expect(defined?(Findbug::AdapterHelper)).to eq("constant")
  end

  describe ".configure" do
    after { Findbug.reset! }

    it "yields the config object and returns it" do
      result = Findbug.configure { |c| c.enabled = false }
      expect(result).to be(Findbug.config)
      expect(Findbug.config.enabled).to be(false)
    end
  end
end
