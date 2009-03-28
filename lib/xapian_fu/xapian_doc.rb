module XapianFu
  class XapianDoc
    attr_reader :fields, :data, :weight, :match
    attr_accessor :id, :db

    def initialize(doc, options = {})
      @fields = {}
      if doc.is_a? Xapian::Match
        match = doc
        doc = match.document
        @match = match
        @weight = @match.weight
      end

      # Handle initialisation from a Xapian::Document, which is
      # usually a search result from a Xapian database
      if doc.is_a?(Xapian::Document)
        @id = doc.docid
        begin
          xdoc_data = Marshal::load(doc.data) unless doc.data.empty?
        rescue ArgumentError
          @data = nil
        end
        if xdoc_data.is_a? Hash
          @data = xdoc_data.delete(:__data)
          @fields = xdoc_data
        else
          @data = xdoc_data
        end
      # Handle initialisation from a hash-like object
      elsif doc.respond_to?("[]") and doc.respond_to?(:has_key?)
        @fields = doc
        @id = doc[:id] if doc.has_key?(:id)
      # Handle initialisation from anything else that can be coerced
      # into a string
      elsif doc.respond_to? :to_s
        @fields = { :content => doc.to_s }
      else
        raise "FIXME: Can't handle indexing that type of object"
      end
      @weight = options[:weight] if options[:weight]
      @data = options[:data] if options[:data]
    end

    # Return a list of terms that the db has for this document
    def terms
      db.ro.termlist(id) if db and db.respond_to?(:ro) and db.ro and id
    end

    # Return a Xapian::Document ready for putting into a Xapian database
    def to_xapian_document
      xdoc = Xapian::Document.new
      stored_fields = fields.reject { |k,v| ! db.store_fields.include? k }
      stored_fields[:__data] = data if data
      xdoc.data = Marshal.dump(stored_fields) unless stored_fields.empty?
      xdoc
    end

    # Return text for indexing from the fields
    def text
      fields.keys.collect { |key| fields[key].to_s }.join(' ')
    end
  end
end
