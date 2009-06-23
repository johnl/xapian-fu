module XapianFu
  
  class XapianDbNotSet < XapianFuError ; end
  class XapianDocNotSet < XapianFuError ; end
  class XapianTypeError < XapianFuError ; end
  
  class XapianDoc
    attr_reader :fields, :data, :weight, :match
    attr_reader :xapian_document
    attr_accessor :id, :db

    # Expects a Xapian::Document, a Hash-like object, or anything that
    # with a to_s method.  Anything else raises a XapianTypeError.
    # Options can be <tt>:weight</tt> to set the search weight or
    # <tt>:data</tt> to set some additional data to be stored with the
    # record in the database.
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
        @xapian_document = doc
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
      elsif doc.respond_to?(:has_key?) and doc.respond_to?("[]")
        @fields = doc
        @id = doc[:id] if doc.has_key?(:id)
      # Handle initialisation from anything else that can be coerced
      # into a string
      elsif doc.respond_to? :to_s
        @fields = { :content => doc.to_s }
      else
        raise XapianTypeError, "Can't handle indexing a '#{doc.class}' object"
      end
      @weight = options[:weight] if options[:weight]
      @data = options[:data] if options[:data]
    end

    # Retrieve the given Xapianvalue from the XapianDb.  <tt>vkey</tt>
    # can be a symbol or string, in which case it's hashed to get an
    # integer value number. Or you can give the integer value number
    # if you know it.
    def get_value(vkey)
      raise XapianDocNotSet unless @xapian_document
      vkey = vkey.to_s.hash unless vkey.is_a? Integer
      @xapian_document.value(vkey)
    end

    # Return a list of terms that the db has for this document.
    def terms
      raise XapianFu::XapianDbNotSet unless db      
      db.ro.termlist(id) if db.respond_to?(:ro) and db.ro and id
    end

    # Return a Xapian::Document ready for putting into a Xapian
    # database. Requires that the db attribute has been set up.
    def to_xapian_document
      raise XapianFu::XapianDbNotSet unless db
      xdoc = Xapian::Document.new
      add_stored_fields_to_xapian_doc(xdoc)
      add_stored_values_to_xapian_doc(xdoc)
      xdoc
    end

    # Return text for indexing from the fields
    def text
      fields_text = fields.keys.collect do |key|
        convert_to_value(fields[key])
      end
      fields_text.join(' ')
    end
    
    def ==(b)
      if b.is_a?(XapianDoc)
        id == b.id
      else
        super(b)
      end
    end
    
    def inspect
      s = ["<#{self.class.to_s} id=#{id}"]
      s << "weight=%.5f" % weight if weight
      s.join(' ') + ">"
    end
    
    private
    
    def add_stored_fields_to_xapian_doc(xdoc)
      # FIXME: performance!
      stored_fields = fields.reject { |k,v| ! db.store_fields.include? k }
      stored_fields[:__data] = data if data
      xdoc.data = Marshal.dump(stored_fields) unless stored_fields.empty?
      xdoc
    end
    
    def add_stored_values_to_xapian_doc(xdoc)
      stored_values = fields.reject { |k,v| ! db.store_values.include? k }
      stored_values.each do |k,v|
        xdoc.add_value(k.to_s.hash, convert_to_value(v))
      end
      xdoc
    end

    private

    def convert_to_value(o)
      if o.respond_to?(:strftime)
        o = o.utc if o.respond_to?(:utc)
        o.strftime("%Y%m%d%H%M%S")
      elsif o.is_a? Integer
        o = "%.10d" % o
      else  
        o.to_s
      end
    end
    
  end
  
  
end
