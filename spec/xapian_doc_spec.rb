require 'xapian'
require 'lib/xapian_fu.rb'
include XapianFu
require 'fileutils'

describe XapianDoc do

  it "should be equal to other XapianDoc objects with the same id" do
    XapianDoc.new(:id => 666).should == XapianDoc.new(:id => 666)
  end
  
  it "should not be equal to other XapianDoc objects with different ids" do
    XapianDoc.new(:id => 666).should_not == XapianDoc.new(:id => 667)
  end

end
