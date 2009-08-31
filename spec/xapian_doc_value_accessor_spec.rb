require 'xapian'
require 'lib/xapian_fu.rb'
include XapianFu
require 'fileutils'

describe XapianDocValueAccessor do

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

  it "should store fields defined as Fixnum as packed Long" do
    xdb = XapianDb.new(:fields => { :number => { :type => Fixnum, :store => true } })
    [-83883, 256532, 0, 0x3fffffff].each do |number|
      doc = xdb.documents.new(:number => number)
      doc.values.store(:number, number, Fixnum).should == number
      doc.values.fetch(:number, Fixnum).should == number
      doc.to_xapian_document.values.first.value.should == [number].pack("l")
    end
  end  

  it "should store fields defined as Bignum as packed Double-precision float, big-endian byte order" do
    xdb = XapianDb.new(:fields => { :number => { :type => Bignum, :store => true } })
    doc = xdb.documents.new(:number => 0x3fffffffffffff)
    doc.values.store(:number, 0x3fffffffffffff).should == 0x3fffffffffffff
    doc.values.fetch(:number).should == 0x3fffffffffffff
    doc.to_xapian_document.values.first.value.should == [0x3fffffffffffff].pack("G")
  end
  
  it "should store fields defined as Float as packed Double-precision float, big-endian byte order" do
    xdb = XapianDb.new(:fields => { :number => { :type => Float, :store => true } })
    [-0.303393984588383833, 8.448488388488384, 1.0].each do |number|
      doc = xdb.documents.new(:number => number)
      doc.values.store(:number, number).should == number
      doc.values.fetch(:number).should == number
      doc.to_xapian_document.values.first.value.should == [number].pack("G")
    end      
  end
  
  it "should store fields defined as Time in UTC as packed Double-precision float, big-endian byte order" do
    xdb = XapianDb.new(:fields => { :created_at => { :type => Time, :store => true }})
    time = Time.now
    doc = xdb.documents.new(:created_at => time)
    doc.values.store(:created_at, time).should == time
    doc.values.fetch(:created_at).should == time
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

end


