module XapianFu
  class XapianDoc
    attr_reader :fields, :data, :weight, :db
    attr_accessor :id
    def initialize(doc, options = {})
      if doc.is_a?(Xapian::Document)
          @id = doc.docid
          # @weight = doc.weight
        begin
          @data = Marshal::load(doc.data) unless doc.data.empty?
        rescue ArgumentError
          @data = nil
        end
      elsif doc.respond_to?("[]")
        @fields = doc
        @id = doc[:id] if doc.respond_to?(:has_key?) and doc.has_key?(:id)
      else
        @fields = { :content => doc.to_s }
      end
      @weight = options[:weight] if options[:weight]
      @data = options[:data] if options[:data]
    end

    def terms
      db.terms(id) if db and id
    end
  end
end
