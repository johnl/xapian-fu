module XapianFu
  class XapianDocValueAccessor
    def initialize(doc)
      @doc = doc
    end
    
    # Add the given <tt>value</tt> with the given <tt>key</tt> to the XapianDoc
    def store(key, value)
      @doc.xapian_document.add_value(value_key(key), value)
      value
    end
    alias_method "[]=", :store
    
    # Retrieve the value with the given <tt>key</tt> from the
    # XapianDoc. <tt>key</tt> can be a symbol or string, in which case
    # it's hashed to get an integer value number. Or you can give the
    # integer value number if you know it.
    #
    # Due to the design of Xapian, if the value does not exist then an
    # empty string is returned.
    def fetch(key)
      @doc.xapian_document.value(value_key(key))
    end
    alias_method "[]", :fetch
    
    # Count the values stored in the XapianDoc
    def size
      @doc.xapian_document.values_count
    end
    
    # Remove the value with the given key from the XapianDoc and return it
    def delete(key)
      value = fetch(key)
      @doc.xapian_document.remove_value(value_key(key))
      value
    end

    private

    # Convert the given key to an integer that can be used as a Xapian
    # value number
    def value_key(key)
      key.is_a?(Integer) ? key : key.to_s.hash
    end    
  end
end
