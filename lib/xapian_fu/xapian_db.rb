module XapianFu
  require 'xapian'
  require 'xapian_doc'
  require 'thread'

  class XapianFuError < StandardError ; end
  class ConcurrencyError < XapianFuError ; end

  class XapianDb
    attr_reader :dir, :db_flag, :query_parser

    def initialize( options = { } )
      @dir = options[:dir]
      @db_flag = Xapian::DB_OPEN
      @db_flag = Xapian::DB_CREATE_OR_OPEN if options[:create]
      @db_flag = Xapian::DB_CREATE_OR_OVERWRITE if options[:overwrite]
      rw.flush if options[:create]
      @tx_mutex = Mutex.new
    end

    # Return the writable Xapian database
    def rw
      @rw ||= setup_rw_db
    end

    # Return the read-only Xapian database
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
    # arbitrary data up to Xmeg can be stored here.
    #
    # Currently, all fields are stored in the database. This will
    # change to store only those fields requested to be stored.
    def add_doc(doc)
      doc = XapianDoc.new(doc) unless doc.is_a? XapianDoc
      doc.db = self
      xdoc = doc.to_xapian_document
      tg = Xapian::TermGenerator.new
      tg.database = rw
      tg.document = xdoc
      tg.index_text( doc.text )
      if doc.id
        rw.replace_document(doc.id, xdoc)
      else
        doc.id = rw.add_document(xdoc)
      end
      doc
    end
    alias_method "<<", :add_doc

    # Conduct a search on the Xapian database, returning an array of 
    # XapianDoc objects for the matches
    def search(q, options = {})
      defaults = { :page => 1, :per_page => 10 }
      options = defaults.merge(options)
      page = options[:page].to_i rescue 1
      page = page > 1 ? page - 1 : 0
      per_page = options[:per_page].to_i rescue 10
      offset = page * per_page
      query = query_parser.parse_query(q, Xapian::QueryParser::FLAG_WILDCARD && Xapian::QueryParser::FLAG_LOVEHATE)
      enquiry.query = query
      enquiry.mset(offset, per_page).matches.collect { |m| XapianDoc.new(m) }
    end

    # Run the given block in a XapianDB transaction.  Any changes to the 
    # Xapian database made in the block will be atomically committed at the end.
    # 
    # If an exception is raised by the block, all changes are discarded and the
    # exception re-raised.
    # 
    # Xapian does not support multiple concurrent transactions on the
    # same Xapian database. Any attempts at this will be serialized by
    # XapianFu, which is not perfect but probably better than just
    # kicking up an exception.
    #
    def transaction
      @tx_mutex.synchronize do
        rw.begin_transaction
        yield
        rw.commit_transaction
      end
    rescue Exception => e
      rw.cancel_transaction
      raise e
    end

    # Flush any changes to disk and reopen the read-only database.
    # Raises ConcurrencyError if a transaction is in process
    def flush
      raise ConcurrencyError if @tx_mutex.locked?
      rw.flush
      ro.reopen
    end

    def query_parser
      unless @query_parser
        @query_parser = Xapian::QueryParser.new
        @query_parser.database = ro
      end
      @query_parser
    end 

    def enquiry
      @enquiry ||= Xapian::Enquire.new(ro)
    end

    private

    def setup_rw_db
      if dir
        @rw = Xapian::WritableDatabase.new(dir, db_flag)
      else
        # In memory database
        @rw = Xapian::inmemory_open
      end
    end

    def setup_ro_db
      if dir
        @ro = Xapian::Database.new(dir)
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

end
