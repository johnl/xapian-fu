require 'xapian'

class XapianDb
  include Xapian
  attr_reader :dir, :db_flag, :query_parser

  def initialize( options )
    @dir = options[:dir]
    @db_flag = DB_OPEN
    @db_flag = DB_CREATE_OR_OPEN if options[:create]
    @db_flag = DB_CREATE_OR_OVERWRITE if options[:overwrite]
  end

  # Return the writable Xapian database
  def db
    @db ||= WritableDatabase.new(dir, db_flag)
  end

  # Add a document to the index. A document is just a hash, the keys representing
  # field names and their values the data to be indexed.
  # 
  # Any value stored with the special key :data is marhalled and stored in the 
  # Xapian database.  Any arbitrary data up to Xmeg can be stored here.  This is
  # often used to store a reference to another data storage system, such as the
  # primary key of an SQL database table.
  def add_doc(doc)
    xdoc = Document.new
    xdoc.data = Marshal.dump(doc.data) if doc.data
    tg = TermGenerator.new
    tg.database = db
    tg.document = xdoc
    tg.index_text( doc.fields.keys.collect { |k| doc.fields[k] }.join(' ') )
    db.add_document(xdoc)
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
    db.flush
  end

  def query_parser
    unless @query_parser
      @query_parser = QueryParser.new
      @query_parser.database = db
    end
    @query_parser
  end 

  def enquiry
    @enquiry ||= Enquire.new(db)
  end
end

class XapianDoc
  attr_reader :fields, :data
  def initialize(fields, options = {})
    @fields = fields
    @weight = options[:weight] if options[:weight]
    @data = options[:data] if options[:data]
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
