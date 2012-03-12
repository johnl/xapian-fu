module XapianFu #:nodoc:

  # The XapianFu::QueryParser is responsible for building useful
  # Xapian::QueryParser objects.
  #
  # The <tt>:fields</tt> option specifies the fields allowed in the
  # query.  Settings <tt>:fields => [:name, :city]</tt> would allow
  # searches such as <tt>"name:john city:Leeds"</tt> (assuming those
  # fields were in the document when it was added to the database.)
  # This options takes an array of symbols or strings representing the
  # field names.
  #
  # The <tt>:database</tt> option specifies the XapianFu::Database,
  # necessary for calculating spelling corrections.  The database's
  # stemmer, stopper and field list will also be used.
  #
  # The <tt>:default_op</tt> option specifies the search operator to
  # be used when not specified.  It takes the operations <tt>:or</tt>,
  # <tt>:phrase</tt>, <tt>:and</tt> and <tt>:and_maybe</tt>.  The
  # default is <tt>:and</tt>.  So for example, with the <tt>:or</tt>
  # operation, a query <tt>"dog cat rabbit"</tt> will be parsed as
  # <tt>"dog AND cat AND rabbit"</tt>.
  #
  # The <tt>:stemming_strategy</tt> option specifies how terms in the
  # query should be stemmed.  It accepts <tt>:some</tt>, <tt>:all</tt>
  # or <tt>:none</tt>.  The default is <tt>:some</tt> which is best
  # for most situations.  See the Xapian documentation for more
  # details.
  #
  # The <tt>:boolean</tt> option enables or disables boolean
  # queries. Set to true or false.
  #
  # The <tt>:boolean_anycase</tt> option enables or disables
  # case-insensitive boolean queries.  Set to true or false.
  #
  # The <tt>:wildcards</tt> option enables or disables the use of
  # wildcard terms in queries, such as <tt>"york*"</tt>. Set to true or false.
  #
  # The <tt>:lovehate</tt> option enables or disables the use of +/-
  # operators in queries, such as <tt>"+mickey -mouse"</tt>. Set to true or
  # false.
  #
  # The <tt>:spelling</tt> option enables or disables spelling
  # correction on queries. Set to true or false. Requires the
  # <tt>:database</tt> option.
  #
  # The <tt>:pure_not</tt> option enables or disables the use of
  # queries that only exclude terms, such as <tt>"NOT apples"</tt>. Set to true
  # or false.
  #
  class QueryParser #:notnew:

    # The stemming strategy to use when generating terms from a query.
    # Defaults to <tt>:some</tt>
    attr_accessor :stemming_strategy

    # The default operation when combining search terms.  Defaults to
    # <tt>:and</tt>
    attr_accessor :default_op

    # The database that this query is agains, used for setting up
    # fields, stemming, stopping and spelling.
    attr_accessor :database

    def initialize(options = { })
      @options = {
        :stemming_strategy => :some,
        :default_op => :and
      }.merge(options)
      self.stemming_strategy = @options[:stemming_strategy]
      self.default_op = @options[:default_op]
      self.database = @options[:database]
    end

    # Parse the given query and return a Xapian::Query object
    # Accepts either a string or a special query
    def parse_query(q)
      case q
      when :all
        Xapian::Query.new("")
      when :nothing
        Xapian::Query.new()
      else
        query_parser.parse_query(q, xapian_flags)
      end
    end

    # Return the query string with any spelling corrections made
    def corrected_query
      query_parser.get_corrected_query_string
    end

    # The current Xapian::QueryParser object
    def query_parser
      if @query_parser
        @query_parser
      else
        qp = Xapian::QueryParser.new
        qp.database = xapian_database if xapian_database
        qp.stopper = database.stopper if database
        qp.stemmer = database.stemmer if database
        qp.default_op = xapian_default_op
        qp.stemming_strategy = xapian_stemming_strategy

        fields.each do |name, type|
          next if database && database.boolean_fields.include?(name)
          qp.add_prefix(name.to_s.downcase, "X" + name.to_s.upcase)
        end

        database.boolean_fields.each do |name|
          qp.add_boolean_prefix(name.to_s.downcase, "X#{name.to_s.upcase}")
        end if database

        database.sortable_fields.each do |field, opts|
          prefix, string = nil

          if opts[:range_postfix]
            prefix = false
            string = opts[:range_postfix]
          else
            prefix = true
            string = opts[:range_prefix] || "#{field.to_s.downcase}:"
          end

          qp.add_valuerangeprocessor(Xapian::NumberValueRangeProcessor.new(
            XapianDocValueAccessor.value_key(field),
            string,
            prefix
          ))
        end if database

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
        valid_flags = [:boolean, :boolean_anycase, :wildcards, :lovehate, :spelling, :pure_not, :synonyms, :phrase]
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
      qflags |= Xapian::QueryParser::FLAG_AUTO_SYNONYMS if flags.include?(:synonyms)
      qflags |= Xapian::QueryParser::FLAG_PHRASE if flags.include?(:phrase)
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

    # An array of field names that will be recognised in this query
    def fields
      if @options[:fields].is_a? Array
        @options[:fields]
      elsif database.is_a? XapianFu::XapianDb
        database.fields
      else
        []
      end
    end
  end
end
