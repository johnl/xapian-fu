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
  # == Spelling suggestions
  #
  # The <tt>:spelling</tt> option controls generation of a spelling
  # dictionary during indexing and its use during searches. When
  # enabled, Xapian will build a dictionary of words for the database
  # whilst indexing documents and will enable spelling suggestion by
  # default for searches.  Building the dictionary will impact
  # indexing performance and database size. It is enabled by default.
  # See the search section for information on getting spelling
  # correction information during searches.
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
  # A more complete way of defining fields is available:
  #
  #   XapianDb.new(:fields => { :title => { :type => String },
  #                             :slug => { :type => String, :index => false },
  #                             :created_at => { :type => Time, :store => true },
  #                             :votes => { :type => Fixnum, :store => true },
  #                           })
  #
  # XapianFu will use the :type option when instantiating a store
  # value, so you'll get back a Time object rather than the result of
  # Time's to_s method as is the default.  Defining the type for
  # numerical classes (such as Time, Fixnum and Bignum) allows
  # XapianFu to to store them on-disk in a much more efficient way,
  # and sort them efficiently (without having to resort to storing
  # leading zeros or anything like that).
  #
  class XapianDb # :nonew:
    # Path to the on-disk database. Nil if in-memory database
    attr_reader :dir
    attr_reader :db_flag #:nodoc:
    # An array of the fields that will be stored in the Xapian
    attr_reader :store_values
    # True if term positions will be stored
    attr_reader :index_positions
    # The default document language. Used for setting up stoppers and stemmers.
    attr_reader :language
    # An hash of field names and their types
    attr_reader :fields
    # An array of fields that will not be indexed
    attr_reader :unindexed_fields
    # Whether this db will generate a spelling dictionary during indexing
    attr_reader :spelling
    attr_reader :sortable_fields

    def initialize( options = { } )
      @options = { :index_positions => true, :spelling => true }.merge(options)
      @dir = @options[:dir]
      @index_positions = @options[:index_positions]
      @db_flag = Xapian::DB_OPEN
      @db_flag = Xapian::DB_CREATE_OR_OPEN if @options[:create]
      @db_flag = Xapian::DB_CREATE_OR_OVERWRITE if @options[:overwrite]
      @tx_mutex = Mutex.new
      @language = @options.fetch(:language, :english)
      @stemmer = @options.fetch(:stemmer, @language)
      @stopper = @options.fetch(:stopper, @language)
      setup_fields(@options[:fields])
      @store_values << @options[:store]
      @store_values << @options[:sortable]
      @store_values << @options[:collapsible]
      @store_values = @store_values.flatten.uniq.compact
      @spelling = @options[:spelling]
    end

    # Return a new stemmer object for this database
    def stemmer
      StemFactory.stemmer_for(@stemmer)
    end

    # The stopper object for this database
    def stopper
      StopperFactory.stopper_for(@stopper)
    end

    # The writable Xapian::WritableDatabase
    def rw
      @rw ||= setup_rw_db
    end

    # The read-only Xapian::Database
    def ro
      @ro ||= setup_ro_db
    end

    # The number of docs in the Xapian database
    def size
      ro.doccount
    end

    # The XapianFu::XapianDocumentsAccessor for this database
    def documents
      @documents_accessor ||= XapianDocumentsAccessor.new(self)
    end

    # Short-cut to documents.add
    def add_doc(doc)
      documents.add(doc)
    end
    alias_method "<<", :add_doc

    # Add a synonym to the database.
    #
    # If you want to search with synonym support, remember to add
    # the option:
    #
    #   db.search("foo", :synonyms => true)
    #
    # Note that in-memory databases don't support synonyms.
    #
    def add_synonym(term, synonym)
      rw.add_synonym(term, synonym)
    end

    # Conduct a search on the Xapian database, returning an array of
    # XapianFu::XapianDoc objects for the matches wrapped in a
    # XapianFu::ResultSet.
    #
    # The <tt>:limit</tt> option sets how many results to return.  For
    # compatability with the <tt>will_paginate</tt> plugin, the
    # <tt>:per_page</tt> option does the same thing (though overrides
    # <tt>:limit</tt>).  Defaults to 10.
    #
    # The <tt>:page</tt> option sets which page of results to return.
    # Defaults to 1.
    #
    # The <tt>:order</tt> option specifies the stored field to order
    # the results by (instead of the default search result weight).
    #
    # The <tt>:reverse</tt> option reverses the order of the results,
    # so lowest search weight first (or lowest stored field value
    # first).
    #
    # The <tt>:collapse</tt> option specifies which stored field value
    # to collapse (group) the results on.  Works a bit like the
    # SQL <tt>GROUP BY</tt> behaviour
    #
    # The <tt>:spelling</tt> option controls whether spelling
    # suggestions will be made for queries. It defaults to whatever
    # the database spelling setting is (true by default).  When
    # enabled, spelling suggestions are available using the
    # XapianFu::ResultSet <tt>corrected_query</tt> method.
    #
    # For additional options on how the query is parsed, see
    # XapianFu::QueryParser

    def search(q, options = {})
      defaults = { :page => 1, :reverse => false,
        :boolean => true, :boolean_anycase => true, :wildcards => true,
        :lovehate => true, :spelling => spelling, :pure_not => false }
      options = defaults.merge(options)
      page = options[:page].to_i rescue 1
      page = page > 1 ? page - 1 : 0
      per_page = options[:per_page] || options[:limit] || 10
      per_page = per_page.to_i rescue 10
      offset = page * per_page
      qp = XapianFu::QueryParser.new({ :database => self }.merge(options))
      query = qp.parse_query(q.to_s)
      query = filter_query(query, options[:filter]) if options[:filter]
      enquiry = Xapian::Enquire.new(ro)
      setup_ordering(enquiry, options[:order], options[:reverse])
      if options[:collapse]
        enquiry.collapse_key = XapianDocValueAccessor.value_key(options[:collapse])
      end
      enquiry.query = query
      ResultSet.new(:mset => enquiry.mset(offset, per_page), :current_page => page + 1,
                    :per_page => per_page, :corrected_query => qp.corrected_query, :xapian_db => self)
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

    private

    # Setup the writable database
    def setup_rw_db
      if dir
        @rw = Xapian::WritableDatabase.new(dir, db_flag)
        @rw.flush if @options[:create]
        @rw
      else
        # In memory database
        @spelling = false # inmemory doesn't support spelling
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
        enquiry.sort_by_value!(XapianDocValueAccessor.value_key(order), reverse)
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
      @sortable_fields = {}
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
        @sortable_fields[name] = {:range_prefix => opts[:range_prefix], :range_postfix => opts[:range_postfix]} if opts[:sortable]
        @unindexed_fields << name if opts[:index] == false
        @fields[name] = opts[:type]
      end
      @fields
    end

    def filter_query(query, filter)
      subqueries = filter.map do |field, values|
        values = Array(values)

        if sortable_fields[field]
          sortable_filter_query(field, values)
        end
      end

      combined_subqueries = Xapian::Query.new(Xapian::Query::OP_AND, subqueries)

      Xapian::Query.new(Xapian::Query::OP_FILTER, query, combined_subqueries)
    end

    def sortable_filter_query(field, values)
      subqueries = values.map do |value|
        from, to = value.split("..")
        slot = XapianDocValueAccessor.value_key(field)

        if from.empty?
          Xapian::Query.new(Xapian::Query::OP_VALUE_LE, slot, Xapian.sortable_serialise(to.to_f))
        elsif to.nil?
          Xapian::Query.new(Xapian::Query::OP_VALUE_GE, slot, Xapian.sortable_serialise(from.to_f))
        else
          Xapian::Query.new(Xapian::Query::OP_VALUE_RANGE, slot, Xapian.sortable_serialise(from.to_f), Xapian.sortable_serialise(to.to_f))
        end
      end

      Xapian::Query.new(Xapian::Query::OP_OR, subqueries)
    end

  end

end

