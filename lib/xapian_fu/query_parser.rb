module XapianFu

  # The XapianFu::QueryParser is responsible for building useful
  # Xapian::QueryParser objects.
  #
  # The <tt>:database</tt> option specifies the XapianFu::Database,
  # necessary for calculating spelling corrections.  The database's 
  # stemmer and stopper will also be used.
  #
  # The <tt>:default_op</tt> option specifies the search operator to
  # be used when not specified.  It takes the operations <tt>:or</tt>,
  # <tt>:phrase</tt>, <tt>:and</tt> and <tt>:and_maybe</tt>.  The
  # default is <tt>:and</tt>.  So for example, with the <tt>:or</tr>
  # operation, a query "dog cat rabbit" will be parsed as "dog AND cat
  # AND rabbit".
  #
  # The <tt>:stemming_strategy</tt> option specifies how terms in the
  # query should be stemmed.  It accepts <tt>:some</tt>, <tt>:all</tt>
  # or <tt>:none</tt>.  The default is <tt>:some</tt> which is best
  # for most situations.  See the Xapian documentation for more
  # details.
  #
  class QueryParser
    
    attr_accessor :stemming_strategy, :default_op, :database

    def initialize(options = { })
      @options = {
        :stemming_strategy => :some,
        :default_op => :and
      }.merge(options)
      self.stemming_strategy = @options[:stemming_strategy]
      self.default_op = @options[:default_op]
      self.database = @options[:database]
    end

    # Parse the given query string and return a Xapian::Query object
    def parse_query(q)
      query_parser.parse_query(q, xapian_flags)
    end

    # Return the query string with any spelling corrections made
    def corrected_query
      query_parser.get_corrected_query_string
    end

    # the current Xapian::QueryParser object
    def query_parser
      if @query_parser
        @query_parser
      else
        qp = Xapian::QueryParser.new
        qp.database = xapian_database
        qp.stopper = database.stopper
        qp.stemmer = database.stemmer
        qp.default_op = xapian_default_op
        qp.stemming_strategy = xapian_stemming_strategy
        @query_parser = qp
      end
    end

    # The Xapian::QueryParser constant for this parsers stemming strategy
    def xapian_stemming_strategy
      case stemming_strategy
      when :all
        Xapian::QueryParser::STEM_ALL
      when :some
        Xapian::QueryParser::STEM_SOME
      when :none
      when false
      when nil
        Xapian::QueryParser::STEM_NONE
      end
    end

    # Return an array of symbols representing the flags set for this
    # query parser
    def flags
      if @flags
        @flags
      else
        valid_flags = [:boolean, :boolean_anycase, :wildcards, :lovehate, :spelling, :pure_not]
        @flags = valid_flags.delete_if { |vf| not @options[vf] }
      end
    end

    # Return a Xapian::QueryParser flag mask representing the flags
    # set for this query parser
    def xapian_flags
      qflags = 0
      qflags |= Xapian::QueryParser::FLAG_BOOLEAN if flags.include?(:boolean)
      qflags |= Xapian::QueryParser::FLAG_BOOLEAN_ANY_CASE if flags.include?(:boolean_anycase)
      qflags |= Xapian::QueryParser::FLAG_WILDCARD if flags.include?(:wildcards)
      qflags |= Xapian::QueryParser::FLAG_LOVEHATE if flags.include?(:lovehate)
      qflags |= Xapian::QueryParser::FLAG_SPELLING_CORRECTION if flags.include?(:spelling)
      qflags |= Xapian::QueryParser::FLAG_PURE_NOT if flags.include?(:pure_not)
      qflags
    end

    # Return a Xapian::Query constant for this query parser's default
    # operation
    def xapian_default_op
      case default_op
      when :and_maybe
        Xapian::Query::OP_AND_MAYBE
      when :or
        Xapian::Query::OP_OR
      when :phrase
        Xapian::Query::OP_PHRASE
      when :and
        Xapian::Query::OP_AND
      end
    end

    # Return the available Xapian::Database for use in the query
    # parser
    def xapian_database
      if database.is_a? XapianFu::XapianDb
        database.ro
      elsif database.is_a? Xapian::Database
        database
      else
        nil
      end
    end
  end
end
