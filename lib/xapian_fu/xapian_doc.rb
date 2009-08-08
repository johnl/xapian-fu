module XapianFu
  require 'xapian_doc_value_accessor'
  
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
      @options = options
      
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
      @db = options[:xapian_db] if options[:xapian_db]
    end

    def data
      @data ||= xapian_document.data
    end

    def values
      @value_accessor ||= XapianDocValueAccessor.new(self)
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
      xdoc.data = data
      add_values_to_xapian_doc(xdoc)
      generate_terms(xdoc)
    end
    
    def xapian_document
      @xapian_document ||= Xapian::Document.new
    end
    
    # Compare IDs with another XapianDoc
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
      s << "db=#{db.nil? ? 'nil' : db}"
      s.join(' ') + ">"
    end

    # Add this document to the Xapian Database, or replace it if it already exists
    def save
      id ? update : create
    end

    # Add this document to the Xapian Database
    def create
      self.id = db.rw.add_document(to_xapian_document)
    end

    # Update this document in the Xapian Database
    def update
      db.rw.replace_document(id, to_xapian_document)
    end
    
    # Set the stemmer to use for this document.  Accepts any string
    # that the Xapian::Stem class accepts (Either the English name for
    # the language or the two letter ISO639 code). Can also be an
    # existing Xapian::Stem object.
    def stemmer=(s)
      @stemmer = StemFactory.stemmer_for(s)
    end

    # Return the stemmer for this document.  If not set on initialize
    # by the :stemmer or :language option, it will try the database's
    # stemmer and otherwise defaults to an English stemmer.
    def stemmer
      if @stemmer
        @stemmer
      else
        @stemmer = 
          if ! @options[:stemmer].nil?
            @options[:stemmer]
          elsif @options[:language]
            @options[:language]
          elsif db
            db.stemmer
          else
            :english
          end
        @stemmer = StemFactory.stemmer_for(@stemmer)
      end
    end
    
    # Return the stopper for this document.  If not set on initialize
    # by the :stopper or :language option, it will try the database's
    # stopper and otherwise default to an English stopper..
    def stopper
      if @stopper
        @stopper
      else
        @stopper =
          if ! @options[:stopper].nil?
            @options[:stopper]
          elsif @options[:language]
            @options[:language]
          elsif db
            db.stopper
          else
            :english
          end
        @stopper = StopperFactory.stopper_for(@stopper)
      end
    end

    # Return this document's language which is set on initialize, inherited 
    # from the database or defaults to :english
    def language
      if @language
        @language
      else
        @language =
          if ! @options[:language].nil?
            @options[:language]
          elsif db and db.language
            db.language
          else
            :english
          end
      end
    end
    
    private
    
    def add_stored_fields_to_xapian_doc(xdoc = Xapian::Document.new)
      # FIXME: performance!
      stored_fields = fields.reject { |k,v| ! db.store_fields.include? k }
      stored_fields[:__data] = data if data
      xdoc.data = Marshal.dump(stored_fields) unless stored_fields.empty?
      xdoc
    end
    
    # Add all the fields to be stored as XapianDb values
    def add_values_to_xapian_doc(xdoc = Xapian::Document.new)
      db.store_values.each do |key|
        xdoc.add_value(key.to_s.hash, convert_to_value(fields[key]))
      end
      xdoc
    end

    # Run the Xapian term generator against this documents text
    def generate_terms(xdoc = Xapian::Document.new)
      tg = Xapian::TermGenerator.new
      tg.database = db.rw
      tg.document = xdoc
      tg.stemmer = stemmer
      tg.stopper = stopper
      index_method = db.index_positions ? :index_text : :index_text_without_positions
      fields.each do |k,v|
        v = convert_to_value(v)
        # add value with field name
        tg.send(index_method, v, 1, 'X' + k.to_s.upcase)
        # add value without field name
        tg.send(index_method, v)
      end
      xdoc
    end

    # Convert the given object into a string suitable for staging as a
    # Xapian value
    def convert_to_value(o)
      if o.respond_to?(:strftime)
        if o.respond_to?(:hour)
          # A Time-like object
          o = o.utc if o.respond_to?(:utc)
          o.strftime("%Y%m%d%H%M%S")
        else
          # A Date-like object
          o.strftime("%Y%m%d")
        end
      elsif o.is_a? Integer
        # Add 10 leading zeros
        o = "%.10d" % o
      else  
        o.to_s
      end
    end
    
  end
  
  
  class StemFactory
    # Return a Xapian::Stem object for the given option. Accepts any
    # string that the Xapian::Stem class accepts (Either the English
    # name for the language or the two letter ISO639 code).
    #
    # If given false or nil, will return a "none" stemmer.
    #
    # It will also accept and return an existing Xapian::Stem object.
    #
    def self.stemmer_for(stemmer)
      if stemmer.is_a? Xapian::Stem
        stemmer
      elsif stemmer.is_a?(String) or stemmer.is_a?(Symbol)
        Xapian::Stem.new(stemmer.to_s)
      else
        Xapian::Stem.new("none")
      end
    end
  end
  
end
