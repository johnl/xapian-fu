module XapianFu #:nodoc:
  # Generic Xapian Fu exception class
  class XapianFuError < StandardError ; end

  require 'xapian'
  require 'xapian_doc'
  require 'stopper_factory'
  require 'query_parser'
  require 'result_set'
  require 'xapian_documents_accessor'
  require 'thread'

  # Raised when two operations are attempted concurrently when it is
  # not possible
  class ConcurrencyError < XapianFuError ; end

  # Raised when a document is requested by id that doesn't exist in
  # the database
  class DocNotFound < XapianFuError ; end

  # The XapianFu::XapianDb encapsulates a Xapian database, handling
  # setting up stemmers, stoppers, query parsers and such.  This is
  # the core of XapianFu.
  #
  # == Opening and creating the database
  #
  # The <tt>:dir</tt> option specified where the xapian database is to
  # be read from and written to.  Without this, an in-memory Xapian
  # database will be used.  By default, the on-disk database will not
  # be created if it doesn't already exist.  See the <tt>:create</tt>
  # option.
  #
  # Setting the <tt>:create</tt> option to <tt>true</tt> will allow
  # XapianDb to create a new Xapian database on-disk. If one already
  # exists, it is just opened. The default is <tt>false</tt>.
  #
  # Setting the <tt>:overwrite</tt> option to <tt>true</tt> will force
  # XapianDb to wipe the current on-disk database and start afresh.
  # The default is <tt>false</tt>.
  #
  #   db = XapianDb.new(:dir => '/tmp/mydb', :create => true)
  #
  # == Language, Stemmers and Stoppers
  #
  # The <tt>:language</tt> option specifies the default document
  # language, and controls the default type of stemmer and stopper
  # that will be used when indexing.  The stemmer and stopper can be
  # overridden with the <tt>:stemmer</tt> and <tt>stopper</tt> options.
  #
  # The <tt>:language, :stemmer and :stopper</tt> options can be set
  # to one of of the following: <tt>:danish, :dutch, :english,
  # :finnish, :french, :german, :hungarian, :italian, :norwegian,
  # :portuguese, :romanian, :russian, :spanish, :swedish,
  # :turkish</tt>.  Set it to <tt>false</tt> to specify none.
  #
  # The default for all is <tt>:english</tt>.
  #
  #   db = XapianDb.new(:language => :italian, :stopper => false)
  #
  # == Fields and values
  #
  # The <tt>:store</tt> option specifies which document fields should
  # be stored in the database. By default, fields are only indexed -
  # the original values cannot be retrieved.
  #
  # The <tt>:sortable</tt> option specifies which document fields will
  # be available for sorting results on.  This is really just does the
  # same thing as <tt>:store</tt> and is just available to be explicit.
  #
  # The <tt>:collapsible</tt> option specifies which document fields
  # can be used to group ("collapse") results.  This also just does
  # the same thing as <tt>:store</tt> and is just available to be explicit.
  #
  # db = XapianDb.new(:store => [:filename], :sortable => [:size])
  # db << { :filename => '/data/music.mp3', :size => 15 }
  # db << { :filename => '/data/sounds.mp3', :size => 33 }
  # FIXME
  #

  class XapianDb
    attr_reader :dir, :db_flag, :query_parser
    attr_reader :store_values, :index_positions, :language
    attr_reader :fields, :unindexed_fields

    def initialize( options = { } )
      @options = { :index_positions => true }.merge(options)
      @dir = @options[:dir]
      @index_positions = @options[:index_positions]
      @db_flag = Xapian::DB_OPEN
      @db_flag = Xapian::DB_CREATE_OR_OPEN if @options[:create]
      @db_flag = Xapian::DB_CREATE_OR_OVERWRITE if @options[:overwrite]
      rw.flush if @options[:create]
      @tx_mutex = Mutex.new
      @language = @options.fetch(:language, :english)
      @stemmer = @options.fetch(:stemmer, @language)
      @stopper = @options.fetch(:stopper, @language)
      setup_fields(@options[:fields])
      @store_values << @options[:store]
      @store_values << @options[:sortable]
      @store_values << @options[:collapsible]      
      @store_values = @store_values.flatten.uniq.compact
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

    # Setup the fields hash and stored_values list from the given options
    def setup_fields(field_options)
      @fields = { }
      @unindexed_fields = []
      @store_values = []
      return nil if field_options.nil?
      default_opts = { 
        :store => true,
        :index => true,
        :type => String
      }
      # Convert array argument to hash, with String as default type
      if field_options.is_a? Array
        fohash = { }
        field_options.each { |f| fohash[f] = { :type => String } }
        field_options = fohash
      end
      field_options.each do |name,opts|
        # Handle simple setup by type only
        opts = { :type => opts } unless opts.is_a? Hash
        opts = default_opts.merge(opts)
        @store_values << name if opts[:store]
        @unindexed_fields << name if opts[:index] == false
        @fields[name] = opts[:type]
      end
      @fields
    end
    
  end
  
end

