require "pg-orm"

module App
  module PGEnumConverter(T)
    def self.from_rs(rs : ::DB::ResultSet)
      T.parse(rs.read(String))
    end

    def self.from_json(pull : JSON::PullParser) : T
      T.parse?(pull.read_string) || pull.raise "Unknown enum #{T} value: #{pull.string_value}"
    end

    def self.to_json(val : T | Nil)
      val.to_s.camelcase
    end

    def self.to_json(val : T | Nil, builder)
      val.try &.to_json(builder)
    end
  end
end
