module XapianFu
  # A XapianDocumentsAccessor is used to provide the
  # XapianDb#documents interface.  It is usually set up by a XapianDb
  # so you shouldn't need to set up your own.
  class XapianDocumentsAccessor
    def initialize(xdb) #:nodoc:
      @xdb = xdb
    end

    # Build a new XapianDoc for this database
    def new(doc = nil, options = { })
      options = options.merge({ :xapian_db => @xdb })
      XapianDoc.new(doc, options)
    end

    # Add a document to the index. A document can be just a hash, the
    # keys representing field names and their values the data to be
    # indexed.  Or it can be a XapianDoc, or any object with a to_s method.
    #
    # If the document has an :id field, it is used as the primary key
    # in the Xapian database.
    #
    # If the document object reponds to the method :data, whatever it
    # returns is marshalled and stored in the  Xapian database.  Any
    # arbitrary data up to Xmeg can be stored here.
    #
    # Currently, all fields are stored in the database. This will
    # change to store only those fields requested to be stored.
    def add(doc)
      doc = XapianDoc.new(doc) unless doc.is_a? XapianDoc
      doc.db = @xdb
      doc.save
      doc
    end
    alias_method "<<", :add

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
        query = Xapian::Query.new(Xapian::Query::OP_VALUE_GE, XapianDocValueAccessor.value_key(key), "0")
        e = Xapian::Enquire.new(@xdb.ro)
        e.query = query
        e.sort_by_value!(XapianDocValueAccessor.value_key(key))
        r = e.mset(0, 1).matches.first
        find(r.docid) rescue nil
      end
    end
  end
end
