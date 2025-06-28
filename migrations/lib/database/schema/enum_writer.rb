# frozen_string_literal: true

require "rake"
require "syntax_tree/rake_tasks"

module Migrations::Database::Schema
  class EnumWriter
    def initialize(namespace, header)
      @namespace = namespace
      @header = header.gsub(/^/, "# ")
    end

    def self.filename_for(enum)
      "#{enum.name.downcase.underscore}.rb"
    end

    def output_enum(enum, output_stream)
      output_stream.puts "# frozen_string_literal: true"
      output_stream.puts
      output_stream.puts @header
      output_stream.puts
      output_stream.puts "module #{@namespace}"
      output_stream.puts "  module #{to_singular_classname(enum.name)}"
      output_stream.puts "    extend Migrations::Enum"
      output_stream.puts
      output_stream.puts enum_values(enum.values)
      output_stream.puts "  end"
      output_stream.puts "end"
    end

    private

    def to_singular_classname(snake_case_string)
      snake_case_string.downcase.singularize.camelize
    end

    def to_const_name(name)
      name.parameterize.underscore.upcase
    end

    def enum_values(values)
      values
        .map
        .with_index(1) { |value, index| "        #{to_const_name(value)} = #{index}" }
        .join("\n")
    end
  end
end
