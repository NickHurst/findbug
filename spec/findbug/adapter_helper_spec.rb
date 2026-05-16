# frozen_string_literal: true

RSpec.describe Findbug::AdapterHelper do
  # Stub ActiveRecord::Base.connection.adapter_name so we can verify the
  # behaviour for every adapter without needing PG / MySQL / SQLite installed.
  def with_adapter(name)
    fake_connection = instance_double("connection", adapter_name: name)
    allow(ActiveRecord::Base).to receive(:connection).and_return(fake_connection)
    yield
  end

  describe ".adapter_name" do
    it "returns the connection adapter name lower-cased" do
      with_adapter("PostgreSQL") do
        expect(described_class.adapter_name).to eq("postgresql")
      end
    end

    it "defaults to 'postgresql' if the connection can't be resolved" do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(StandardError)
      expect(described_class.adapter_name).to eq("postgresql")
    end
  end

  describe "adapter predicates" do
    {
      "PostgreSQL" => :postgresql?,
      "PostGIS"    => :postgresql?,
      "Mysql2"     => :mysql?,
      "MySQL"      => :mysql?,
      "SQLite"     => :sqlite?
    }.each do |name, predicate|
      it "recognises #{name} via #{predicate}" do
        with_adapter(name) do
          expect(described_class.public_send(predicate)).to be true
        end
      end
    end

    it "returns false for predicates that don't match" do
      with_adapter("PostgreSQL") do
        expect(described_class.mysql?).to be false
        expect(described_class.sqlite?).to be false
      end
    end
  end

  describe ".json_column_type" do
    it "returns :jsonb on PostgreSQL" do
      with_adapter("PostgreSQL") do
        expect(described_class.json_column_type).to eq(:jsonb)
      end
    end

    it "returns :jsonb on PostGIS (PostgreSQL extension)" do
      with_adapter("PostGIS") do
        expect(described_class.json_column_type).to eq(:jsonb)
      end
    end

    it "returns :json on MySQL" do
      with_adapter("Mysql2") do
        expect(described_class.json_column_type).to eq(:json)
      end
    end

    it "returns :text on SQLite" do
      with_adapter("SQLite") do
        expect(described_class.json_column_type).to eq(:text)
      end
    end

    it "falls back to :text for unknown adapters" do
      with_adapter("Trilogy") do
        expect(described_class.json_column_type).to eq(:text)
      end
    end
  end

  describe ".json_default" do
    it "returns the value verbatim on PostgreSQL (jsonb accepts Hash/Array)" do
      with_adapter("PostgreSQL") do
        expect(described_class.json_default({})).to eq({})
        expect(described_class.json_default([])).to eq([])
      end
    end

    it "returns nil on MySQL (json columns don't allow literal defaults)" do
      with_adapter("Mysql2") do
        expect(described_class.json_default({})).to be_nil
        expect(described_class.json_default([])).to be_nil
      end
    end

    it "returns a JSON-encoded string on SQLite (text columns need strings)" do
      with_adapter("SQLite") do
        expect(described_class.json_default({})).to eq("{}")
        expect(described_class.json_default([])).to eq("[]")
        expect(described_class.json_default(foo: "bar")).to eq('{"foo":"bar"}')
      end
    end
  end

  describe ".date_trunc_sql" do
    context "on PostgreSQL" do
      it "emits native date_trunc for each interval" do
        with_adapter("PostgreSQL") do
          expect(described_class.date_trunc_sql("minute", "captured_at"))
            .to eq("date_trunc('minute', captured_at)")
          expect(described_class.date_trunc_sql("hour", "captured_at"))
            .to eq("date_trunc('hour', captured_at)")
          expect(described_class.date_trunc_sql("day", "captured_at"))
            .to eq("date_trunc('day', captured_at)")
        end
      end
    end

    context "on MySQL" do
      it "uses DATE_FORMAT for minute/hour and DATE() for day" do
        with_adapter("Mysql2") do
          expect(described_class.date_trunc_sql("minute", "captured_at"))
            .to eq("DATE_FORMAT(captured_at, '%Y-%m-%d %H:%i:00')")
          expect(described_class.date_trunc_sql("hour", "captured_at"))
            .to eq("DATE_FORMAT(captured_at, '%Y-%m-%d %H:00:00')")
          expect(described_class.date_trunc_sql("day", "captured_at"))
            .to eq("DATE(captured_at)")
        end
      end
    end

    context "on SQLite" do
      it "uses strftime for minute/hour and DATE() for day" do
        with_adapter("SQLite") do
          expect(described_class.date_trunc_sql("minute", "captured_at"))
            .to eq("strftime('%Y-%m-%d %H:%M:00', captured_at)")
          expect(described_class.date_trunc_sql("hour", "captured_at"))
            .to eq("strftime('%Y-%m-%d %H:00:00', captured_at)")
          expect(described_class.date_trunc_sql("day", "captured_at"))
            .to eq("DATE(captured_at)")
        end
      end
    end

    it "defaults to the hour bucket when given an unknown interval" do
      with_adapter("PostgreSQL") do
        expect(described_class.date_trunc_sql("decade", "captured_at"))
          .to eq("date_trunc('hour', captured_at)")
      end

      with_adapter("Mysql2") do
        expect(described_class.date_trunc_sql("decade", "captured_at"))
          .to eq("DATE_FORMAT(captured_at, '%Y-%m-%d %H:00:00')")
      end

      with_adapter("SQLite") do
        expect(described_class.date_trunc_sql("decade", "captured_at"))
          .to eq("strftime('%Y-%m-%d %H:00:00', captured_at)")
      end
    end
  end
end
