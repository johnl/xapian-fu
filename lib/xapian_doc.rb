module XapianFu
  class XapianDoc
    attr_reader :fields, :data, :id
    def initialize(fields, options = {})
      if fields.is_a?(Xapian::Document)
        begin
          xdoc = fields
          @data = Marshal::load(xdoc.data) unless xdoc.data.empty?
          @id = xdoc.docid
        rescue ArgumentError
          @data = nil
        end
      else
        @fields = fields
        @id = fields[:id] if fields.has_key?(:id)
        @weight = options[:weight] if options[:weight]
        @data = options[:data] if options[:data]
      end
    end
  end
end
