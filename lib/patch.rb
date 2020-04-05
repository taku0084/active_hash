module ActiveHash
  class Base

    class << self
      def all
        ActiveHash::Relation.new(self, @records || [])
      end

      def find_using_index(id)
        index = record_index[id.to_s]
        index && @records[index]
      end
    end
  end

  class Relation

    attr_accessor :records

    def initialize(klass, records)
      self.klass = klass
      self.records = records
    end

    def where(query_hash = {})
      return self if query_hash.blank?

      filtered_records = records.select do |record|
        match_options?(record, query_hash)
      end

      ActiveHash::Relation.new(klass, filtered_records)
    end

    def not(query_hash)
      return ActiveHash::Relation.new(klass, records) if query_hash.blank?

      filtered_records = records.reject do |record|
        match_options?(record, query_hash)
      end

      ActiveHash::Relation.new(klass, filtered_records)
    end

    def all
      where
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
      if scoped?
        find_by(id: id)
      else
        klass.find_using_index(id)
      end
    end

    def order(*options)
      check_if_method_has_arguments!(:order, options)
      relation = where({})
      return relation if options.blank?

      processed_args = preprocess_order_args(options)
      candidates = relation.records.dup

      order_by_args!(candidates, processed_args)

      candidates
    end

    private

    def match_options?(record, options)
      options.keys.all? do |col|
        match = options[col]
        record_value = record[col]
        if match.is_a?(Array)
          match.any? { |val| normalize(col, record_value) == normalize(col, val) }
        elsif match.is_a?(Range)
          match.include?(record_value)
        else
          normalize(col, record_value) == normalize(col, match)
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

    def scoped?
      klass.data && klass.data.size != records.size
    end
  end
end
