# frozen_string_literal: true

module Findbug
  module AdapterHelper
    def self.adapter_name
      ActiveRecord::Base.connection.adapter_name.downcase
    rescue StandardError
      "postgresql"
    end

    def self.postgresql?
      name = adapter_name
      name.include?("postgresql") || name.include?("postgis")
    end

    def self.mysql?
      adapter_name.include?("mysql")
    end

    def self.sqlite?
      adapter_name.include?("sqlite")
    end

    # Returns the appropriate column type symbol for JSON storage.
    # :jsonb on PostgreSQL, :json on MySQL, :text on SQLite.
    def self.json_column_type
      if postgresql?
        :jsonb
      elsif mysql?
        :json
      else
        :text
      end
    end

    # Returns an adapter-appropriate column default for a JSON field.
    #
    # PostgreSQL jsonb accepts a Hash/Array directly.
    # MySQL JSON columns don't support DEFAULT values (pre-8.0.13), so we return nil.
    # SQLite text columns need a JSON-encoded String.
    def self.json_default(value)
      if postgresql?
        value
      elsif mysql?
        nil
      else
        value.to_json
      end
    end

    # Returns adapter-specific SQL to truncate a timestamp column to an interval.
    # interval: 'minute', 'hour', or 'day' (anything else falls back to 'hour')
    # column:   SQL column name, e.g. 'captured_at'
    def self.date_trunc_sql(interval, column)
      bucket = %w[minute hour day].include?(interval) ? interval : "hour"

      if postgresql?
        "date_trunc('#{bucket}', #{column})"
      elsif mysql?
        case bucket
        when "minute" then "DATE_FORMAT(#{column}, '%Y-%m-%d %H:%i:00')"
        when "day"    then "DATE(#{column})"
        else               "DATE_FORMAT(#{column}, '%Y-%m-%d %H:00:00')"
        end
      else # SQLite and unknown adapters
        case bucket
        when "minute" then "strftime('%Y-%m-%d %H:%M:00', #{column})"
        when "day"    then "DATE(#{column})"
        else               "strftime('%Y-%m-%d %H:00:00', #{column})"
        end
      end
    end
  end
end
