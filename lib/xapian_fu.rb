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

  def db
    @db ||= WritableDatabase.new(dir, db_flag)
  end

  def <<(doc)
    xdoc = Document.new
    xdoc.data = Marshal.dump(doc.data) if doc.data
    tg = TermGenerator.new
    tg.database = db
    tg.document = xdoc
    tg.index_text( doc.fields.keys.collect{|k|doc.fields[k]}.join(' ') )
    db.add_document(xdoc)
  end

  def search(q, options = {})
    defaults = { :offset => 0, :limit => 10 }
    options = defaults.merge(options)
    query = query_parser.parse_query(q, QueryParser::FLAG_WILDCARD && QueryParser::FLAG_LOVEHATE)
    enquiry.query = query
    enquiry.mset(options[:offset], options[:limit]).matches.collect { |m| XapianResult.new(m) }
  end

  def transaction
    db.begin_transaction
    yield
    db.commit_transaction
  rescue Exception => e
    db.cancel_transaction
    raise e
  end

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
