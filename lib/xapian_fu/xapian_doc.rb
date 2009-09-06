class Time
  def to_xapian_fu_string
    utc.strftime("%Y%m%d%H%M%S")
  end
end

class Date
  def to_xapian_fu_string
    strftime("%Y%m%d")
  end
end

require 'date'

class DateTime
  def to_xapian_fu_string
    strftime("%Y%m%d%H%M%S")
  end
end

module XapianFu
  require 'xapian_doc_value_accessor'
  
  class XapianDbNotSet < XapianFuError ; end
  class XapianDocNotSet < XapianFuError ; end
  class XapianTypeError < XapianFuError ; end

  # A XapianDoc represents a document in a XapianDb.
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

    # The arbitrary data stored in the Xapian database with this
    # document.  Returns an empty string if none available.
    def data
      @data ||= xapian_document.data
    end

    # The XapianFu::XapianDocValueAccessor for accessing the values in
    # this document.
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
      xapian_document.data = data
      # Clear and add values
      xapian_document.clear_values
      add_values_to_xapian_document
      # Clear and add terms
      xapian_document.clear_terms      
      generate_terms
      xapian_document
    end

    # The Xapian::Document for this XapianFu::Document.  If this
    # document was retrieved from a XapianDb then this will have been
    # initialized by Xapian, otherwise a new Xapian::Document.new is
    # allocated.
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

    # Add this document to the Xapian Database, or replace it if it
    # already exists.
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
    
    # Array of field names not to run through the TermGenerator
    def unindexed_fields
      db ? db.unindexed_fields : []
    end
    
    # Add all the fields to be stored as XapianDb values
    def add_values_to_xapian_document
      db.store_values.collect do |key|
        values[key] = fields[key]
        key
      end
    end

    # Run the Xapian term generator against this documents text
    def generate_terms
      tg = Xapian::TermGenerator.new
      tg.database = db.rw
      tg.document = xapian_document
      tg.stopper = stopper
      tg.stemmer = stemmer      
      index_method = db.index_positions ? :index_text : :index_text_without_positions
      fields.each do |k,v|
        next if unindexed_fields.include?(k)
        if v.respond_to?(:to_xapian_fu_string)
          v = v.to_xapian_fu_string
        else
          v = v.to_s
        end
        # add value with field name
        tg.send(index_method, v, 1, 'X' + k.to_s.upcase)
        # add value without field name
        tg.send(index_method, v)
      end
      xapian_document
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
