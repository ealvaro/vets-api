# frozen_string_literal: true

require 'rails_helper'

# Guards that the PostGIS adapter dumps vets-api's 6 spatial columns correctly
# after the Rails 7.2 -> 8.1 upgrade. Context: https://va.ghe.com/software/vets-api/pull/29083
RSpec.describe 'PostGIS schema round-trip', type: :model do
  # (table, column, st_type)
  expected_spatial_columns = [
    %w[accredited_individuals location st_point],
    %w[accredited_organizations location st_point],
    %w[base_facilities location st_point],
    %w[drivetime_bands polygon st_polygon],
    %w[veteran_organizations location st_point],
    %w[veteran_representatives location st_point]
  ].freeze

  # Rails 8 SchemaDumper.dump takes the connection POOL, not a raw connection.
  def dump_schema
    io = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
    io.string
  end

  # Matches on semantic content, tolerating both hashrocket (7.2) and colon (8.1) Hash syntax.
  def spatial_line_regex(column, st_type)
    /t\.geography\s+"#{Regexp.escape(column)}".*
      srid(?:=>|:\s*)4326.*
      type(?:=>|:\s*)"#{Regexp.escape(st_type)}".*
      geographic(?:=>|:\s*)true/x
  end

  let(:dump) { dump_schema }

  it 'dumps exactly the expected number of geography columns' do
    expect(dump.scan(/t\.geography\s/).size).to eq(expected_spatial_columns.size)
  end

  expected_spatial_columns.each do |table, column, st_type|
    it "round-trips the #{table}.#{column} spatial column (#{st_type}, srid 4326, geographic)" do
      table_block = dump[/create_table "#{Regexp.escape(table)}".*?\n  end/m]
      expect(table_block).not_to be_nil,
                                 "table #{table} missing from schema dump entirely"
      expect(table_block).to match(spatial_line_regex(column, st_type)),
                             "#{table}.#{column} did not dump as #{st_type}/srid:4326/geographic:true — " \
                             'PostGIS adapter may be incompatible with this Rails version'
    end
  end

  it 'preserves NOT NULL on drivetime_bands.polygon' do
    polygon_line = dump[/t\.geography\s+"polygon".*$/]
    expect(polygon_line).to include('null: false')
  end

  # dump -> load into scratch schema -> re-dump -> byte-identical. Opt-in (slower).
  it 'produces a stable dump across a load/redump cycle', :postgis_full_roundtrip do
    first = dump_schema.scan(/t\.geography.*$/)
    conn = ActiveRecord::Base.connection
    conn.execute('DROP SCHEMA IF EXISTS roundtrip_scratch CASCADE')
    conn.execute('CREATE SCHEMA roundtrip_scratch')
    # Include public so PostGIS types (geography/geometry) resolve during load.
    conn.schema_search_path = 'roundtrip_scratch,public'
    ActiveRecord::Schema.verbose = false
    load Rails.root.join('db', 'schema.rb')
    second = dump_schema.scan(/t\.geography.*$/)
    expect(second).to eq(first)
  ensure
    conn = ActiveRecord::Base.connection
    conn.schema_search_path = 'public'
    conn.execute('DROP SCHEMA IF EXISTS roundtrip_scratch CASCADE')
  end
end
