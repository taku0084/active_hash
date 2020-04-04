module ActiveHash
  class Relation
    include Enumerable

    delegate :each, to: :records # Make Enumerable work
    delegate :equal?, :==, :===, :eql?, :sort!, to: :records
    delegate :empty?, :length, :first, :second, :third, :last, to: :records
    delegate :sample, to: :records

    def initialize(klass, all_records, query_hash = nil)
      self.klass = klass
      self.all_records = all_records
      self.query_hash = query_hash
      self.records_dirty = false
      self
    end

    def where(query_hash = {})
      return self if query_hash.blank?

      filtered_records = all_records.select do |record|
        match_options?(record, query_hash)
      end
      ActiveHash::Relation.new(klass, filtered_records)
    end

    def not(query_hash)
      return ActiveHash::Relation.new(klass, all_records) if query_hash.blank?

      filtered_records = all_records.reject do |record|
        match_options?(record, query_hash)
      end
      ActiveHash::Relation.new(klass, filtered_records)
    end

    def all
      where({})
    end

    def find_by(options)
      where(options).first
    end

    def find_by!(options)
      find_by(options) || (raise RecordNotFound.new("Couldn't find #{klass.name}"))
    end

    def find(id = nil, &block)
      case id
        when Array
          id.map { |i| find(i) }
        when nil
          raise RecordNotFound.new("Couldn't find #{klass.name} without an ID") unless block_given?
          records.find(&block) # delegate to Enumerable#find if a block is given
        else
          find_by_id(id) || begin
            raise RecordNotFound.new("Couldn't find #{klass.name} with ID=#{id}")
          end
      end
    end

    def find_by_id(id)
      find_by(id: id)
    end

    def count
      length
    end

    def pluck(*column_names)
      column_names.map { |column_name| all.map(&column_name.to_sym) }.inject(&:zip)
    end

    def pick(*column_names)
      pluck(*column_names).first
    end

    def reload
      @records = filter_all_records_by_query_hash
    end

    def order(*options)
      check_if_method_has_arguments!(:order, options)
      relation = where({})
      return relation if options.blank?

      processed_args = preprocess_order_args(options)
      candidates = relation.dup

      order_by_args!(candidates, processed_args)

      candidates
    end

    def to_ary
      records.dup
    end


    attr_reader :query_hash, :klass, :all_records, :records_dirty

    private

    attr_writer :query_hash, :klass, :all_records, :records_dirty

    def records
      if @records.nil? || records_dirty
        reload
      else
        @records
      end
    end

    def filter_all_records_by_query_hash
      self.records_dirty = false
      all_records
    end

    def match_options?(record, options)
      options.all? do |col, match|
        attr = record[col]
        if match.is_a?(Array)
          match.any? { |val| normalize(col, attr) == normalize(col, val) }
        elsif match.is_a?(Range)
          match.include?(attr)
        else
          normalize(col, attr) == normalize(col, match)
        end
      end
    end

    def normalize(field_name, value)
      case
      when field_name == :id
        value.to_i
      when value.respond_to?(:to_sym)
        value.to_sym
      else
        value
      end
    end

    def check_if_method_has_arguments!(method_name, args)
      return unless args.blank?

      raise ArgumentError,
            "The method .#{method_name}() must contain arguments."
    end

    def preprocess_order_args(order_args)
      order_args.reject!(&:blank?)
      return order_args.reverse! unless order_args.first.is_a?(String)

      ary = order_args.first.split(', ')
      ary.map! { |e| e.split(/\W+/) }.reverse!
    end

    def order_by_args!(candidates, args)
      args.each do |arg|
        field, dir = if arg.is_a?(Hash)
                       arg.to_a.flatten.map(&:to_sym)
                     elsif arg.is_a?(Array)
                       arg.map(&:to_sym)
                     else
                       arg.to_sym
                     end

        candidates.sort! do |a, b|
          if dir.present? && dir.to_sym.upcase.equal?(:DESC)
            b[field] <=> a[field]
          else
            a[field] <=> b[field]
          end
        end
      end
    end
  end
end
