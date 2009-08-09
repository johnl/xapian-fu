module XapianFu
  class XapianFuError < StandardError ; end

  require 'xapian'
  require 'xapian_doc'
  require 'stopper_factory'
  require 'query_parser'
  require 'result_set'
  require 'xapian_documents_accessor'
  require 'thread'

  class ConcurrencyError < XapianFuError ; end
  class DocNotFound < XapianFuError ; end

  class XapianDb
    attr_reader :dir, :db_flag, :query_parser
    attr_reader :store_values, :index_positions, :language

    def initialize( options = { } )
      options = { :index_positions => true }.merge(options)
      @dir = options[:dir]
      @index_positions = options[:index_positions]
      @db_flag = Xapian::DB_OPEN
      @db_flag = Xapian::DB_CREATE_OR_OPEN if options[:create]
      @db_flag = Xapian::DB_CREATE_OR_OVERWRITE if options[:overwrite]
      @store_values = []
      @store_values << options[:store]
      @store_values << options[:sortable]
      @store_values << options[:collapsible]
      @store_values = @store_values.flatten.uniq.compact
      rw.flush if options[:create]
      @tx_mutex = Mutex.new
      @language = options[:language] || :english
      @stemmer = options[:stemmer] || @language
      @stopper = options[:stopper] || @language
    end
    
    # Return a new stemmer object for this database
    def stemmer
      StemFactory.stemmer_for(@stemmer)
    end
    
    # Return the stopper object for this database
    def stopper
      StopperFactory.stopper_for(@stopper)
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

    def add_doc(doc)
      documents.add(doc)
    end
    alias_method "<<", :add_doc

    # Conduct a search on the Xapian database, returning an array of 
    # XapianDoc objects for the matches
    def search(q, options = {})
      defaults = { :page => 1, :reverse => false, 
        :boolean => true, :boolean_anycase => true, :wildcards => true, 
        :lovehate => true, :spelling => true, :pure_not => false }
      options = defaults.merge(options)
      page = options[:page].to_i rescue 1
      page = page > 1 ? page - 1 : 0
      per_page = options[:per_page] || options[:limit] || 10
      per_page = per_page.to_i rescue 10
      offset = page * per_page
      qp = XapianFu::QueryParser.new({ :database => self }.merge(options))
      query = qp.parse_query(q.to_s)
      setup_ordering(enquiry, options[:order], options[:reverse]) 
      if options[:collapse]
        enquiry.collapse_key = options[:collapse].to_s.hash
      end
      enquiry.query = query
      ResultSet.new(:mset => enquiry.mset(offset, per_page), :current_page => page + 1, 
                    :per_page => per_page, :corrected_query => qp.corrected_query)
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
  end
end
