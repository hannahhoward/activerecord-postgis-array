require 'activerecord-postgis-adapter'
require 'ipaddr'
require 'pg_array_parser'

module ActiveRecord
  module ConnectionAdapters
    module PostGISAdapter
      class IndexDefinition
        attr_accessor :using, :where, :index_opclass
      end

      SpatialColumn.class_eval do
        include PgArrayParser
        attr_accessor :array

        def initialize_with_extended_types(name, default, sql_type = nil, null = true, opts = {})
          if sql_type =~ /\[\]$/
            @array = true
            initialize_without_extended_types(name, default, sql_type[0..sql_type.length - 3], null, opts)
            @sql_type = sql_type
          else
            initialize_without_extended_types(name,default, sql_type, null, opts)
          end
        end
        alias_method_chain :initialize, :extended_types

        def type_cast_with_extended_types(value)
          return nil if value.nil?
          return coder.load(value) if encoded?

          klass = self.class
          if self.array && String === value && value.start_with?('{') && value.end_with?('}')
            string_to_array value
          elsif self.array && Array === value
            value
          else
              type_cast_without_extended_types(value)
          end
        end
        alias_method_chain :type_cast, :extended_types

        def string_to_array(value)
          if Array === value
            value
          else
            string_array = parse_pg_array value
            if type == :string || type == :text
              force_character_encoding(string_array)
            else
              type_cast_array(string_array)
            end
          end
        end

        def type_cast_array(array)
          array.map do |value|
            Array === value ? type_cast_array(value) : type_cast(value)
          end
        end

        def number?
          !self.array && super
        end

        def type_cast_code_with_extended_types(var_name)
          klass = self.class.name

          if self.array
            "#{klass}.new('#{self.name}', #{self.default.nil? ? 'nil' : "'#{self.default}'"}, '#{self.sql_type}').string_to_array(#{var_name})"
          else
            type_cast_code_without_extended_types(var_name)
          end
        end
        alias_method_chain :type_cast_code, :extended_types

        private

        def force_character_encoding(string_array)
          string_array.map do |item|
            item.respond_to?(:force_encoding) ? item.force_encoding(ActiveRecord::Base.connection.encoding_for_ruby) : item
          end
        end
      end

      MainAdapter.class_eval do
        class UnsupportedFeature < Exception; end

        class ColumnDefinition < ActiveRecord::ConnectionAdapters::ColumnDefinition
          attr_accessor :array
        end

        class SpatialTableDefinition

          def column(name, type=nil, options = {})
            super

            column = self[name]
            column.array     = options[:array]

            self
          end

          private

          def new_column_definition(base, name, type)
            definition = ColumnDefinition.new base, name, type
            @columns << definition
            @columns_hash[name] = definition
            definition
          end
        end

        # Translate from the current database encoding to the encoding we
        # will force string array components into on retrievial.
        def encoding_for_ruby
          @database_encoding ||= case ActiveRecord::Base.connection.encoding
                                 when 'UTF8'
                                   'UTF-8'
                                 else
                                   ActiveRecord::Base.connection.encoding
                                 end
        end

        def supports_extensions?
          postgresql_version > 90100
        end

        def add_column_options!(sql, options)
          if options[:array] || options[:column].try(:array)
            sql << '[]'
          end
          super
        end

        def add_index(table_name, column_name, options = {})
          index_name, unique, index_columns, _ = add_index_options(table_name, column_name, options)
          if options.is_a? Hash
            index_type = options[:using] ? " USING #{options[:using]} " : ""
            index_type = 'USING GIST' if options[:spatial]
            index_options = options[:where] ? " WHERE #{options[:where]}" : ""
            index_opclass = options[:index_opclass]
            index_algorithm = options[:algorithm] == :concurrently ? ' CONCURRENTLY' : ''

            if options[:algorithm].present? && options[:algorithm] != :concurrently
              raise ArgumentError.new 'Algorithm must be one of the following: :concurrently'
            end
          end
          execute "CREATE #{unique} INDEX#{index_algorithm} #{quote_column_name(index_name)} ON #{quote_table_name(table_name)}#{index_type}(#{index_columns} #{index_opclass})#{index_options}"
        end

        def add_extension(extension_name, options={})
          raise UnsupportedFeature.new('Extensions are not support by this version of PostgreSQL') unless supports_extensions?
          execute "CREATE extension IF NOT EXISTS \"#{extension_name}\""
        end

        def change_table(table_name, options = {})
          if supports_bulk_alter? && options[:bulk]
            recorder = ActiveRecord::Migration::CommandRecorder.new(self)
            yield Table.new(table_name, recorder)
            bulk_change_table(table_name, recorder.commands)
          else
            yield Table.new(table_name, self)
          end
        end

        if RUBY_PLATFORM =~ /java/
          # The activerecord-jbdc-adapter implements PostgreSQLAdapter#add_column differently from the active-record version
          # so we have to patch that version in JRuby, but not in MRI/YARV
          def add_column(table_name, column_name, type, options = {})
            default = options[:default]
            notnull = options[:null] == false
            sql_type = type_to_sql(type, options[:limit], options[:precision], options[:scale])

            if options[:array]
              sql_type << '[]'
            end

            # Add the column.
            execute("ALTER TABLE #{quote_table_name(table_name)} ADD COLUMN #{quote_column_name(column_name)} #{sql_type}")

            change_column_default(table_name, column_name, default) if options_include_default?(options)
            change_column_null(table_name, column_name, false, default) if notnull
          end
        end

        def type_cast_extended(value, column, part_array = false)
          case value
          when NilClass
            if column.array && part_array
              'NULL'
            elsif column.array && !part_array
              value
            else
              type_cast_without_extended_types(value, column)
            end
          when Array
            if column.array
              array_to_string(value, column)
            else
              type_cast_without_extended_types(value, column)
            end
          else
            type_cast_without_extended_types(value, column)
          end
        end

        def type_cast_with_extended_types(value, column)
          type_cast_extended(value, column)
        end
        alias_method_chain :type_cast, :extended_types

        def quote_with_extended_types(value, column = nil)
          if value.is_a? Array
            "'#{array_to_string(value, column, true)}'"
          elsif column.respond_to?(:array) && column.array && value =~ /^\{.*\}$/
            "'#{value}'"
          else
            quote_without_extended_types(value, column)
          end
        end
        alias_method_chain :quote, :extended_types

        def opclasses
          @opclasses ||= select_rows('SELECT opcname FROM pg_opclass').flatten.uniq
        end

        # this is based upon rails 4 changes to include different index methods
        # Returns an array of indexes for the given table.
        def indexes(table_name_, name_ = nil)
          opclasses
          # FULL REPLACEMENT. RE-CHECK ON NEW VERSIONS.
          result_ = query(<<-SQL, 'SCHEMA')
            SELECT distinct i.relname, d.indisunique, d.indkey, pg_get_indexdef(d.indexrelid), t.oid
            FROM pg_class t
            INNER JOIN pg_index d ON t.oid = d.indrelid
            INNER JOIN pg_class i ON d.indexrelid = i.oid
            WHERE i.relkind = 'i'
              AND d.indisprimary = 'f'
              AND t.relname = '#{table_name_}'
              AND i.relnamespace IN (SELECT oid FROM pg_namespace WHERE nspname = ANY (current_schemas(false)) )
            ORDER BY i.relname
          SQL

          result_.map do |row_|
            index_name_ = row_[0]
            unique_ = row_[1] == 't'
            indkey_ = row_[2].split(" ")
            inddef_ = row_[3]
            oid_ = row_[4]

            columns_ = query(<<-SQL, "SCHEMA")
              SELECT a.attnum, a.attname, t.typname
                FROM pg_attribute a, pg_type t
              WHERE a.attrelid = #{oid_}
                AND a.attnum IN (#{indkey_.join(",")})
                AND a.atttypid = t.oid
            SQL
            columns_ = columns_.inject({}){ |h_, r_| h_[r_[0].to_s] = [r_[1], r_[2]]; h_ }
            column_names_ = columns_.values_at(*indkey_).compact.map{ |a_| a_[0] }

            # add info on sort order for columns (only desc order is explicitly specified, asc is the default)
            desc_order_columns_ = inddef_.scan(/(\w+) DESC/).flatten
            orders_ = desc_order_columns_.any? ? Hash[desc_order_columns_.map {|order_column_| [order_column_, :desc]}] : {}
            where_ = inddef_.scan(/WHERE (.+)$/).flatten[0]
            spatial_ = inddef_ =~ /using\s+gist/i && columns_.size == 1 &&
              (columns_.values.first[1] == 'geometry' || columns_.values.first[1] == 'geography')

            using_ = inddef_.scan(/USING (.+?) /).flatten[0].to_sym
            if using_
              index_op_ = inddef_.scan(/USING .+? \(.+? (#{opclasses.join('|')})\)/).flatten
              index_op_ = index_op_[0].to_sym if index_op_.present?
            end

            if column_names_.present?
              index_def_ = ::RGeo::ActiveRecord::SpatialIndexDefinition.new(table_name_, index_name_, unique_, column_names_, [], orders_, where_, spatial_ ? true : false)
              index_def_.using = using_ if using_ && using_ != :btree && !spatial_
              index_def_.index_opclass = index_op_ if using_ && using_ != :btree && !spatial_ && index_op_
              index_def
            else 
              nil
            end
            #/changed
          end.compact
        end

        def extensions
          select_rows('select extname from pg_extension', 'extensions').map { |row| row[0] }.delete_if {|name| name == 'plpgsql'}
        end

        private

        def array_to_string(value, column, encode_single_quotes = false)
          "{#{value.map { |val| item_to_string(val, column, encode_single_quotes) }.join(',')}}"
        end

        def item_to_string(value, column, encode_single_quotes = false)
          return 'NULL' if value.nil?

          casted_value = type_cast_extended(value, column, true)

          if casted_value.is_a?(String) && value.is_a?(String)
            casted_value = casted_value.dup
            # Encode backslashes.  One backslash becomes 4 in the resulting SQL.
            # (why 4, and not 2?  Trial and error shows 4 works, 2 fails to parse.)
            casted_value.gsub!('\\', '\\\\\\\\')
            # Encode a bare " in the string as \"
            casted_value.gsub!('"', '\\"')
            # PostgreSQL parses the string values differently if they are quoted for
            # use in a statement, or if it will be used as part of a bound argument.
            # For directly-inserted values (UPDATE foo SET bar='{"array"}') we need to
            # escape ' as ''.  For bound arguments, do not escape them.
            if encode_single_quotes
              casted_value.gsub!("'", "''")
            end

            "\"#{casted_value}\""
          else
            casted_value
          end
        end
      end
    end
  end
end
