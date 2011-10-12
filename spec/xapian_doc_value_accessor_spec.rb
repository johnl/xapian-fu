require 'xapian'
require File.expand_path('../lib/xapian_fu.rb', File.dirname(__FILE__))
include XapianFu
require 'fileutils'
require 'fixtures/film_data'

describe XapianDocValueAccessor do

  describe "value_key" do
    it "should return the crc32 of the given string" do
      XapianDocValueAccessor.value_key("louisa").should == 4040578532
    end
  end

  it "should store and fetch values like a hash" do
    values = XapianDocValueAccessor.new(XapianDoc.new(nil))
    values.store(:city, "Leeds").should == "Leeds"
    values.fetch(:city).should == "Leeds"
    values[:city] = "London"
    values[:city].should == "London"
  end

  it "should add and retrieve values from the Xapian::Document" do
    doc = XapianDoc.new(nil)
    values = XapianDocValueAccessor.new(doc)
    lambda { values[:city] = "London" }.should change(doc.xapian_document, :values_count).by(1)
  end

  it "should store fields defined as Fixnum as packed double-precision float, network byte order" do
    xdb = XapianDb.new(:fields => { :number => { :type => Fixnum, :store => true } })
    [-83883, 256532, 0, 0xffffff].each do |number|
      doc = xdb.documents.new(:number => number)
      doc.values.store(:number, number, Fixnum).should == number
      doc.values.fetch(:number, Fixnum).should == number
      doc.to_xapian_document.values.first.value.should == [number].pack("G")
    end
  end

  it "should store fields defined as Bignum as packed double-precision float, network byte order" do
    xdb = XapianDb.new(:fields => { :number => { :type => Bignum, :store => true } })
    [
     (-0x1fffffffffffff..-0x1fffffffffffff + 10).to_a,
     (0x1fffffffffffff-10..0x1fffffffffffff).to_a
    ].flatten.each do |number|
      doc = xdb.documents.new(:number => number)
      doc.values.store(:number, number, Bignum).should == number
      doc.values.fetch(:number, Bignum).should == number
      doc.to_xapian_document.values.first.value.should == [number].pack("G")
    end
  end

  it "should raise an error when attempting to store Bignum values bigger or smaller than can be stored" do
    xdb = XapianDb.new(:fields => { :number => { :type => Bignum, :store => true } })
    [-(0x1fffffffffffff+1), 0x1fffffffffffff+1].each do |number|
      doc = xdb.documents.new(:number => number)
      lambda {  doc.values.store(:number, number, Bignum) }.should raise_error XapianFu::ValueOutOfBounds
    end
  end

  it "should store fields defined as Float as packed double-precision float, network byte order" do
    xdb = XapianDb.new(:fields => { :number => { :type => Float, :store => true } })
    [-0.303393984588383833, 8.448488388488384, 1.0].each do |number|
      doc = xdb.documents.new(:number => number)
      doc.values.store(:number, number).should == number
      doc.values.fetch(:number).should == number
      doc.to_xapian_document.values.first.value.should == [number].pack("G")
    end
  end

  it "should store fields defined as Time in UTC as packed double-precision float, network byte order" do
    xdb = XapianDb.new(:fields => { :created_at => { :type => Time, :store => true }})
    time = Time.now
    doc = xdb.documents.new(:created_at => time)
    doc.values.store(:created_at, time).should == time
    doc.values.fetch(:created_at).should be_close(time, 0.0001) # ignore milliseconds
    doc.to_xapian_document.values.first.value.should == [time.utc.to_f].pack("G")
  end

  it "should store fields defined as DateTime as a string" do
    xdb = XapianDb.new(:fields => { :created_at => { :type => DateTime, :store => true }})
    datetime = DateTime.now
    doc = xdb.documents.new(:created_at => datetime)
    doc.values.store(:created_at, datetime).should == datetime
    doc.values.fetch(:created_at).should be_close(datetime, 0.0001) # miliseconds are not stored
    doc.to_xapian_document.values.first.value.should == datetime.to_s
  end

  it "should store fields defined as Date as a string" do
    xdb = XapianDb.new(:fields => { :created_on => { :type => Date, :store => true }})
    date = Date.today
    doc = xdb.documents.new(:created_on => date)
    doc.values.store(:created_on, date).should == date
    doc.values.fetch(:created_on).should == date
    doc.to_xapian_document.values.first.value.should == date.to_s
  end

  it "should count the stored values when size is called" do
    doc = XapianDoc.new(nil)
    lambda { doc.values[:city] = "London" }.should change(doc.values, :size).by(1)
  end

  it "should delete values from the Xapian::Document" do
    doc = XapianDoc.new(nil)
    doc.values[:city] = "Leeds"
    lambda { doc.values.delete(:city) }.should change(doc.values, :size).by(-1)
    doc.values[:city] = "London"
    doc.values.delete(:city).should == "London"
  end

  film_data_path = File.join(File.dirname(__FILE__), "fixtures/film_data")
  Dir.foreach(film_data_path) do |db_path|
    next unless db_path =~ /.+~.+/
    it "should read stored values from databases created by #{db_path}" do
      db = XapianDb.new(:dir => File.join(film_data_path, db_path),
                        :fields => {
                          :title => { :type => String, :store => true },
                          :released_on => { :type => Date, :store => true },
                          :revenue => { :type => Integer, :store => true }
                        })
      FILM_DATA.size.times do |i|
        doc = db.documents[i+1]
        [:title, :released_on, :revenue].each do |field|
          doc.values[field].should === FILM_DATA[i][field]
        end
      end

      db.search("cold mountain")[0].values[:revenue].should == 173_013_509
    end
  end

end


