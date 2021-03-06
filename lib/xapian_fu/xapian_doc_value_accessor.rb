require 'zlib'

class Integer #:nodoc:
  def self.to_xapian_fu_storage_value(value)
    if value > 0x1fffffffffffff or value < -0x1fffffffffffff
      raise XapianFu::ValueOutOfBounds
    end
    [value].pack("G")
  end

  def self.from_xapian_fu_storage_value(value)
    value.unpack("G").first.truncate rescue nil
  end
end

if RUBY_VERSION < '2.4'
  class Bignum #:nodoc:
    def self.to_xapian_fu_storage_value(value)
      if value > 0x1fffffffffffff or value < -0x1fffffffffffff
        raise XapianFu::ValueOutOfBounds
      end
      [value].pack("G")
    end

    def self.from_xapian_fu_storage_value(value)
      value.unpack("G").first.truncate rescue nil
    end
  end

  class Fixnum #:nodoc:
    def self.to_xapian_fu_storage_value(value)
      [value].pack("G")
    end

    def self.from_xapian_fu_storage_value(value)
      value.unpack("G").first.truncate rescue nil
    end
  end
end

class Float #:nodoc:
  def self.to_xapian_fu_storage_value(value)
    [value].pack("G")
  end

  def self.from_xapian_fu_storage_value(value)
    value.unpack("G").first rescue nil
  end
end

class Time #:nodoc:
  def self.to_xapian_fu_storage_value(value)
    [value.utc.to_f].pack("G")
  end

  def self.from_xapian_fu_storage_value(value)
    Time.at(value.unpack("G").first) rescue nil
  end
end

class Date #:nodoc:
  def self.to_xapian_fu_storage_value(value)
    value.to_s
  end

  def self.from_xapian_fu_storage_value(value)
    self.parse(value) rescue nil
  end
end

class Object
  def self.to_xapian_fu_storage_value(value)
    value.to_s
  end

  def self.from_xapian_fu_storage_value(value)
    value
  end
end

module XapianFu #:nodoc:

  class ValueOutOfBounds < XapianFuError
  end

  # A XapianDocValueAccessor is used to provide the XapianDoc#values
  # interface to read and write field values to a XapianDb.  It is
  # usually set up by a XapianDoc so you shouldn't need to set up your
  # own.
  class XapianDocValueAccessor

    def initialize(xapian_doc)
      @doc = xapian_doc
    end

    # Add the given <tt>value</tt> with the given <tt>key</tt> to the
    # XapianDoc.  If the value has a
    # <tt>to_xapian_fu_storage_value</tt> method then it is used to
    # generate the final value to be stored, otherwise <tt>to_s</tt>
    # is used.  This is usually paired with a
    # <tt>from_xapian_fu_storage_value</tt> class method on retrieval.
    def store(key, value, type = nil)
      converted_value = @doc.db.serialize_value(key, value, type)
      @doc.xapian_document.add_value(XapianDocValueAccessor.value_key(key), converted_value)
      value
    end
    alias_method "[]=", :store

    # Retrieve the value with the given <tt>key</tt> from the
    # XapianDoc. <tt>key</tt> can be a symbol or string, in which case
    # it's hashed to get an integer value number. Or you can give the
    # integer value number if you know it.
    #
    # If the class specified in the database fields for this key (or
    # as the optional argument) has a
    # <tt>from_xapian_fu_storage_value</tt> method then it is used to
    # instaniate the object from the stored value.  This is usually
    # paired with a <tt>to_xapian_fu_storage_value</tt> instance
    # method.
    #
    # Due to the design of Xapian, if the value does not exist then an
    # empty string is returned.
    def fetch(key, type = nil)
      value = @doc.xapian_document.value(XapianDocValueAccessor.value_key(key))
      @doc.db.unserialize_value(key, value, type)
    end
    alias_method "[]", :fetch

    # Count the values stored in the XapianDoc
    def size
      @doc.xapian_document.values_count
    end

    # Remove the value with the given key from the XapianDoc and return it
    def delete(key)
      value = fetch(key)
      @doc.xapian_document.remove_value(XapianDocValueAccessor.value_key(key))
      value
    end

    # Convert the given key to an integer that can be used as a Xapian
    # value number
    def self.value_key(key)
      (key.is_a?(Integer) ? key : Zlib.crc32(key.to_s))
    end
  end
end
