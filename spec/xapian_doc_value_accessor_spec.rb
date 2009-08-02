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


