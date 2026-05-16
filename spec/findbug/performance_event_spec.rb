# frozen_string_literal: true

RSpec.describe Findbug::PerformanceEvent do
  let(:valid_attrs) do
    {
      transaction_name: "GET /users",
      duration_ms: 120.5,
      captured_at: Time.now
    }
  end

  describe "validations" do
    it "is valid with required attributes" do
      expect(described_class.new(valid_attrs)).to be_valid
    end

    it "requires transaction_name" do
      e = described_class.new(valid_attrs.merge(transaction_name: nil))
      expect(e).not_to be_valid
    end

    it "requires duration_ms" do
      e = described_class.new(valid_attrs.merge(duration_ms: nil))
      expect(e).not_to be_valid
    end

    it "rejects negative duration_ms" do
      e = described_class.new(valid_attrs.merge(duration_ms: -1))
      expect(e).not_to be_valid
    end
  end

  describe "JSON accessors on text columns" do
    let(:event) { described_class.new(valid_attrs) }

    it "round-trips slow_queries as an Array" do
      event.slow_queries = [{ sql: "SELECT 1", duration_ms: 5 }]
      event.save!
      reloaded = described_class.find(event.id)
      expect(reloaded.slow_queries).to eq([{ "sql" => "SELECT 1", "duration_ms" => 5 }])
    end

    it "round-trips n_plus_one_queries as an Array" do
      event.n_plus_one_queries = [{ sql: "X", count: 3 }]
      event.save!
      expect(described_class.find(event.id).n_plus_one_queries)
        .to eq([{ "sql" => "X", "count" => 3 }])
    end

    it "round-trips context as a Hash" do
      event.context = { tag: "perf" }
      event.save!
      expect(described_class.find(event.id).context).to eq("tag" => "perf")
    end

    it "returns the right empty default for each field when DB value is nil" do
      event.save!
      event.update_columns(slow_queries: nil, n_plus_one_queries: nil, context: nil)
      reloaded = event.reload
      expect(reloaded.slow_queries).to eq([])
      expect(reloaded.n_plus_one_queries).to eq([])
      expect(reloaded.context).to eq({})
    end

    it "doesn't double-encode a pre-serialised JSON String" do
      event.slow_queries = '[{"already":"json"}]'
      event.save!
      raw = described_class.connection.select_value(
        "SELECT slow_queries FROM findbug_performance_events WHERE id = #{event.id}"
      )
      expect(raw).to eq('[{"already":"json"}]')
      expect(event.reload.slow_queries).to eq([{ "already" => "json" }])
    end

    it "stores nil when assigned nil" do
      event.context = nil
      event.save!
      raw = described_class.connection.select_value(
        "SELECT context FROM findbug_performance_events WHERE id = #{event.id}"
      )
      expect(raw).to be_nil
    end

    it "returns the field-specific empty default if the stored value is malformed JSON" do
      event.save!
      event.update_columns(
        slow_queries: "not json",
        n_plus_one_queries: "broken",
        context: "garbage"
      )
      reloaded = event.reload
      expect(reloaded.slow_queries).to eq([])
      expect(reloaded.n_plus_one_queries).to eq([])
      expect(reloaded.context).to eq({})
    end
  end

  describe "JSON accessors on jsonb/json columns" do
    let(:event) { described_class.new(valid_attrs) }

    before do
      allow(described_class).to receive(:columns_hash).and_return(
        "slow_queries"       => instance_double("col", type: :jsonb),
        "n_plus_one_queries" => instance_double("col", type: :jsonb),
        "context"            => instance_double("col", type: :json)
      )
    end

    it "passes Arrays through to write_attribute unchanged" do
      expect(event).to receive(:write_attribute).with(:slow_queries, [{ x: 1 }])
      event.slow_queries = [{ x: 1 }]
    end

    it "passes Hashes through to write_attribute unchanged" do
      expect(event).to receive(:write_attribute).with(:context, { tag: "y" })
      event.context = { tag: "y" }
    end

    it "passes nil through unchanged" do
      expect(event).to receive(:write_attribute).with(:context, nil)
      event.context = nil
    end
  end

  describe ".create_from_event" do
    let(:event_data) do
      {
        transaction_name: "GET /widgets",
        transaction_type: "request",
        request_method: "GET",
        request_path: "/widgets",
        duration_ms: 88.0,
        db_time_ms: 12.0,
        query_count: 4,
        slow_queries: [{ sql: "SELECT *", ms: 60 }],
        has_n_plus_one: true,
        context: { plan: "pro" },
        captured_at: Time.now
      }
    end

    it "persists a new event from a Hash payload" do
      expect { described_class.create_from_event(event_data) }
        .to change(described_class, :count).by(1)
    end

    it "decodes JSON fields after save" do
      e = described_class.create_from_event(event_data)
      expect(e.reload.slow_queries).to eq([{ "sql" => "SELECT *", "ms" => 60 }])
      expect(e.reload.context).to eq("plan" => "pro")
    end

    it "accepts a String for captured_at" do
      ts = "2025-01-02T03:04:05Z"
      e = described_class.create_from_event(event_data.merge(captured_at: ts))
      expect(e.captured_at).to be_within(1.0).of(Time.parse(ts))
    end

    it "defaults captured_at to current time when missing" do
      e = described_class.create_from_event(event_data.merge(captured_at: nil))
      expect(e.captured_at).to be_within(2.0).of(Time.now)
    end
  end

  describe ".aggregate_for" do
    before do
      [50, 100, 150, 200, 250].each do |d|
        described_class.create!(valid_attrs.merge(duration_ms: d, captured_at: Time.now))
      end
    end

    it "returns nil when there are no matching events" do
      expect(described_class.aggregate_for("GET /none")).to be_nil
    end

    it "computes count, min, max, and avg correctly" do
      stats = described_class.aggregate_for("GET /users")
      expect(stats[:count]).to eq(5)
      expect(stats[:min_duration_ms]).to eq(50)
      expect(stats[:max_duration_ms]).to eq(250)
      expect(stats[:avg_duration_ms]).to eq(150.0)
    end

    it "computes percentiles" do
      stats = described_class.aggregate_for("GET /users")
      expect(stats[:p50_duration_ms]).to eq(150)
      # interpolated, just confirm it falls in the high band
      expect(stats[:p95_duration_ms]).to be_between(200, 250).inclusive
      expect(stats[:p99_duration_ms]).to be_between(240, 250).inclusive
    end
  end

  describe ".slowest_transactions" do
    before do
      described_class.create!(valid_attrs.merge(transaction_name: "fast",
                                                duration_ms: 10,
                                                captured_at: Time.now))
      described_class.create!(valid_attrs.merge(transaction_name: "slow",
                                                duration_ms: 900,
                                                captured_at: Time.now))
    end

    it "orders transactions by average duration descending" do
      rows = described_class.slowest_transactions
      expect(rows.first[:transaction_name]).to eq("slow")
      expect(rows.last[:transaction_name]).to eq("fast")
    end
  end

  describe ".n_plus_one_hotspots" do
    before do
      2.times do
        described_class.create!(valid_attrs.merge(transaction_name: "GET /a",
                                                  has_n_plus_one: true,
                                                  query_count: 25,
                                                  captured_at: Time.now))
      end
      described_class.create!(valid_attrs.merge(transaction_name: "GET /b",
                                                has_n_plus_one: false,
                                                captured_at: Time.now))
    end

    it "returns only transactions flagged with N+1" do
      rows = described_class.n_plus_one_hotspots
      expect(rows.map { |r| r[:transaction_name] }).to eq(["GET /a"])
      expect(rows.first[:n_plus_one_count]).to eq(2)
    end
  end

  describe ".throughput_over_time" do
    before do
      # Two events, recent enough to fall in the default 24h window.
      described_class.create!(valid_attrs.merge(captured_at: Time.now,    duration_ms: 100))
      described_class.create!(valid_attrs.merge(captured_at: Time.now - 60, duration_ms: 200))
    end

    it "returns rows with :time (a Time-like value), :count, and :avg_duration_ms" do
      rows = described_class.throughput_over_time
      expect(rows).not_to be_empty
      row = rows.first
      expect(row).to include(:time, :count, :avg_duration_ms)
      # The :time value should respond to strftime (the view calls it that way).
      expect(row[:time]).to respond_to(:strftime)
    end

    it "uses the AdapterHelper-provided SQL for grouping" do
      expect(Findbug::AdapterHelper).to receive(:date_trunc_sql)
        .with("hour", "captured_at")
        .at_least(:once)
        .and_call_original
      described_class.throughput_over_time(interval: "hour")
    end

    it "accepts 'minute', 'hour', and 'day' intervals without error" do
      %w[minute hour day].each do |interval|
        expect { described_class.throughput_over_time(interval: interval) }.not_to raise_error
      end
    end
  end
end
