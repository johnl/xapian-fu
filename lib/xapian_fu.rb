require 'xapian'

module XapianFu

  class XapianDb
    include Xapian
    attr_reader :dir, :db_flag, :query_parser

    def initialize( options = { } )
      @dir = options[:dir]
      @db_flag = DB_OPEN
      @db_flag = DB_CREATE_OR_OPEN if options[:create]
      @db_flag = DB_CREATE_OR_OVERWRITE if options[:overwrite]
    end

    # Return the writable Xapian database
    def rw
      @rw ||= setup_rw_db
    end

    def ro
      @ro ||= setup_ro_db
    end

    # Return the number of docs in the Xapian database
    def size
      ro.doccount
    end

    # Return the XapianDocumentsAccessor for this database
    def documents
      @documents_accessor ||= XapianDocumentsAccessor.new(self)
    end

    # Add a document to the index. A document can be just a hash, the
    # keys representing field names and their values the data to be
    # indexed.  Or it can be a XapianDoc, or any object with a to_s method.
    # 
    # If the document object reponds to the method :data, whatever it
    # returns is marshalled and stored in the  Xapian database.  Any
    # arbitrary data up to Xmeg can be stored here.  This is often used
    # to store a reference to another data storage system, such as the
    # primary key of an SQL database table.
    def add_doc(doc)
      xdoc = Document.new
      if doc.respond_to?(:data) and doc.data
        xdoc.data = Marshal.dump(doc.data)
      end
      tg = TermGenerator.new
      tg.database = rw
      tg.document = xdoc

      if doc.respond_to?(:fields)
        fields = doc.fields
      elsif doc.is_a? Hash
        fields = doc
      else
        fields = { :content => doc.to_s }
      end

      content = fields.keys.collect { |k| fields[k] }.join(' ')
      
      tg.index_text( content )
      rw.add_document(xdoc)
    end
    alias_method "<<", :add_doc

    # Conduct a search on the Xapian database, returning an array of 
    # XapianResult objects
    def search(q, options = {})
      defaults = { :offset => 0, :limit => 10 }
      options = defaults.merge(options)
      query = query_parser.parse_query(q, QueryParser::FLAG_WILDCARD && QueryParser::FLAG_LOVEHATE)
      enquiry.query = query
      enquiry.mset(options[:offset], options[:limit]).matches.collect { |m| XapianResult.new(m) }
    end

    # Run the given block in a XapianDB transaction.  Any changes to the 
    # Xapian database made in the block will be atomically committed at the end.
    # 
    # If an exception is raised by the block, all changes are discarded and the
    # exception re-raised.
    #
    def transaction
      db.begin_transaction
      yield
      db.commit_transaction
    rescue Exception => e
      db.cancel_transaction
      raise e
    end

    # Flush any changes to disk.
    def flush
      rw.flush
    end

    def query_parser
      unless @query_parser
        @query_parser = QueryParser.new
        @query_parser.database = ro
      end
      @query_parser
    end 

    def enquiry
      @enquiry ||= Enquire.new(ro)
    end

    private

    def setup_rw_db
      if dir
        @rw = WritableDatabase.new(dir, db_flag)
      else
        # In memory database
        @rw = inmemory_open
      end
    end

    def setup_ro_db
      if dir
        @ro = Database.new(dir)
      else
        # In memory db
        @ro = rw
      end
    end

    #
    class XapianDocumentsAccessor
      def initialize(xdb)
        @xdb = xdb
      end

      def [](doc_id)
        xdoc = @xdb.ro.document(doc_id)
        XapianDoc.new(xdoc)
      end
    end
  end

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

  # A XapianResult objects represents a document in the Xapian DB that matched
  # a query.
  class XapianResult
    attr_reader :score, :percent, :doc, :data, :id
    def initialize(match)
      @score = match.weight
      @percent = match.percent
      @doc = match.document
      @id = @doc.docid
      @data = Marshal.load(@doc.data) unless @doc.data.empty?
    end
  end
end
