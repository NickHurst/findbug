# frozen_string_literal: true

require "active_record"
require "sqlite3"
require "logger"

# Configure ActiveRecord with an in-memory SQLite database for tests.
# SQLite uses :text columns for our JSON fields, which exercises the
# adapter-agnostic serialisation path. Tests that need to assert
# PostgreSQL or MySQL behaviour stub the connection adapter directly.
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = Logger.new(IO::NULL)
ActiveRecord::Schema.verbose = false

require "findbug"
require_relative "../app/models/findbug/error_event"
require_relative "../app/models/findbug/performance_event"

ActiveRecord::Schema.define do
  create_table :findbug_error_events, force: true do |t|
    t.string   :fingerprint, null: false
    t.string   :exception_class, null: false
    t.text     :message
    t.text     :backtrace
    t.text     :context,      default: "{}"
    t.text     :request_data, default: "{}"
    t.string   :environment
    t.string   :release_version
    t.string   :severity, default: "error"
    t.string   :source
    t.boolean  :handled, default: false
    t.integer  :occurrence_count, default: 1
    t.datetime :first_seen_at
    t.datetime :last_seen_at
    t.string   :status, default: "unresolved"
    t.timestamps
  end

  create_table :findbug_performance_events, force: true do |t|
    t.string   :transaction_name, null: false
    t.string   :transaction_type, default: "request"
    t.string   :request_method
    t.string   :request_path
    t.string   :format
    t.integer  :status
    t.float    :duration_ms, null: false
    t.float    :db_time_ms, default: 0
    t.float    :view_time_ms, default: 0
    t.integer  :query_count, default: 0
    t.text     :slow_queries,       default: "[]"
    t.text     :n_plus_one_queries, default: "[]"
    t.boolean  :has_n_plus_one, default: false
    t.integer  :view_count, default: 0
    t.text     :context, default: "{}"
    t.string   :environment
    t.string   :release_version
    t.datetime :captured_at
    t.timestamps
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Roll back DB writes between examples so tests don't pollute each other.
  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
