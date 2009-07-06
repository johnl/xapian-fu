module XapianFu
  class XapianFuError < StandardError ; end

  require 'xapian'
  require 'xapian_doc'
  require 'thread'

  class ConcurrencyError < XapianFuError ; end
  class DocNotFound < XapianFuError ; end

  # A XapianFu::ResultSet holds the XapianDoc objects returned from a search.
  # It acts just like an array but is decorated with useful attributes.
  class ResultSet < Array
    
    # The Xapian match set for this search 
    attr_reader :mset
    attr_reader :current_page, :per_page
    # The total number of pages of results available for this search
    attr_reader :total_pages
    
    # nodoc
    def initialize(options = { })
      @mset = options[:mset]
      @current_page = options[:current_page]
      @per_page = options[:per_page]
      concat mset.matches.collect { |m| XapianDoc.new(m) }      
    end
    
    # The estimated total number of matches this search could return
    def total_entries
      mset.matches_estimated
    end
    
    # The estimated total number of pages of results this search could return
    def total_pages
      (total_entries / per_page.to_f).round
    end
    
    # The previous page number, or nil if there are no previous pages available
    def previous_page
      p = current_page - 1
      p == 0 ? nil : p
    end
    
    # The next page number, or nil if there are no more more pages available
    def next_page
      p = current_page + 1
      p > total_pages ? nil : p
    end
    
    # The offset within the total results of the first result in this page
    def offset
      (current_page - 1) * per_page
    end
    
  end

  class XapianDb
    attr_reader :dir, :db_flag, :query_parser
    attr_reader :store_fields, :store_values
    attr_reader :index_positions

    def initialize( options = { } )
      options = { :index_positions => true }.merge(options)
      @dir = options[:dir]
      @index_positions = options[:index_positions]
      @db_flag = Xapian::DB_OPEN
      @db_flag = Xapian::DB_CREATE_OR_OPEN if options[:create]
      @db_flag = Xapian::DB_CREATE_OR_OVERWRITE if options[:overwrite]
      @store_fields = Array.new(1, options[:store]).compact
      @store_values = Array.new(1, options[:sortable]).compact
      @store_values += Array.new(1, options[:collapsible]).compact
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
      if index_positions
        tg.index_text(doc.text)
      else
        tg.index_text_without_positions(doc.text)
      end
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
      defaults = { :page => 1, :reverse => false }
      options = defaults.merge(options)
      page = options[:page].to_i rescue 1
      page = page > 1 ? page - 1 : 0
      per_page = options[:per_page] || options[:limit] || 10
      per_page = per_page.to_i rescue 10
      offset = page * per_page
      query = query_parser.parse_query(q, Xapian::QueryParser::FLAG_WILDCARD && Xapian::QueryParser::FLAG_LOVEHATE)
      setup_ordering(enquiry, options[:order], options[:reverse]) 
      if options[:collapse]
        enquiry.collapse_key = options[:collapse].to_s.hash
      end
      enquiry.query = query
      ResultSet.new(:mset => enquiry.mset(offset, per_page), :current_page => page + 1, 
                    :per_page => per_page)
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
    def transaction(flush_on_commit = true)
      @tx_mutex.synchronize do
        begin
          rw.begin_transaction(flush_on_commit)
          yield
        rescue Exception => e
          rw.cancel_transaction
          ro.reopen
          raise e
        end
        rw.commit_transaction
        ro.reopen
      end
    end

    # Flush any changes to disk and reopen the read-only database.
    # Raises ConcurrencyError if a transaction is in process
    def flush
      raise ConcurrencyError if @tx_mutex.locked?
      rw.flush
      ro.reopen
    end
    
    # return the current Xapian::QueryParser object, or create a new one
    def query_parser
      unless @query_parser
        @query_parser = Xapian::QueryParser.new
        @query_parser.database = ro
      end
      @query_parser
    end 

    # return the current Xapian::Enquire object, or create a new one
    def enquiry
      @enquiry ||= Xapian::Enquire.new(ro)
    end

    private

    # Setup the writable database
    def setup_rw_db
      if dir
        @rw = Xapian::WritableDatabase.new(dir, db_flag)
      else
        # In memory database
        @rw = Xapian::inmemory_open
      end
    end

    # Setup the read-only database
    def setup_ro_db
      if dir
        @ro = Xapian::Database.new(dir)
      else
        # In memory db
        @ro = rw
      end
    end
    
    # Setup ordering for the given Xapian::Enquire objects
    def setup_ordering(enquiry, order = nil, reverse = true)
      if order.to_s == "id"
        # Sorting by a value that doesn't exist falls back to docid ordering
        enquiry.sort_by_value!((1 << 32)-1, reverse)
        enquiry.docid_order = reverse ? Xapian::Enquire::DESCENDING : Xapian::Enquire::ASCENDING
      elsif order.is_a? String or order.is_a? Symbol
        enquiry.sort_by_value!(order.to_s.hash, reverse)
      else
        enquiry.sort_by_relevance!
      end
      enquiry
    end
    
    # A XapianDocumentsAccessor is used to provide the XapianDb#documents interface
    class XapianDocumentsAccessor
      def initialize(xdb)
        @xdb = xdb
      end

      # Return the document with the given id from the
      # database. Raises a XapianFu::DocNotFoundError exception 
      # if it doesn't exist.
      def find(doc_id)
        xdoc = @xdb.ro.document(doc_id)
        XapianDoc.new(xdoc, :xapian_db => @xdb)
      rescue RuntimeError => e
        raise e.to_s =~ /^DocNotFoundError/ ? XapianFu::DocNotFound : e
      end

      # Return the document with the given id from the database or nil
      # if it doesn't exist
      def [](doc_id)
        find(doc_id)
      rescue XapianFu::DocNotFound
        nil
      end

      # Delete the given document from the database and return the
      # document id, or nil if it doesn't exist
      def delete(doc)
        if doc.respond_to?(:to_i)
          @xdb.rw.delete_document(doc.to_i)
          doc.to_i
        end
      rescue RuntimeError => e
        raise e unless e.to_s =~ /^DocNotFoundError/
      end
      
      # Return the document with the highest value in the specified field or nil if it doesn't exist
      def max(key = :id)
        if key == :id
          # for :id we can use lastdocid
          find(@xdb.ro.lastdocid) rescue nil
        else
          # for other values, we do a search ordered by that key in descening order
          query = Xapian::Query.new(Xapian::Query::OP_VALUE_GE, key.to_s.hash, "0")
          e = Xapian::Enquire.new(@xdb.ro)
          e.query = query
          e.sort_by_value!(key.to_s.hash)
          r = e.mset(0, 1).matches.first
          find(r.docid) rescue nil
        end
      end
    end
  end

end
