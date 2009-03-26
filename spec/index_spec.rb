require 'xapian'
require 'lib/xapian_fu.rb'

tmp_dir = '/tmp/xapian_fu_test.db'

describe XapianDb do

  it "should make an in-memory database by default" do
    xdb = XapianDb.new
    xdb.ro.should be_a_kind_of(Xapian::Database)
    xdb.rw.should == xdb.ro
  end
  
  it "should make an on-disk database when given a :dir option" do
    xdb = XapianDb.new(:dir => tmp_dir, :create => true)
    xdb.should respond_to(:dir)
    xdb.dir.should == tmp_dir
    xdb.ro.should be_a_kind_of(Xapian::Database)
    xdb.rw.should be_a_kind_of(Xapian::WritableDatabase)
  end

  it "should index a XapianDoc" do
    xdb = XapianDb.new
    xdb << XapianDoc.new({ :text => "once upon a time", :title => "A story" })
    xdb.flush
    xdb.size.should == 1
  end

  it "should index a Hash" do
    xdb = XapianDb.new
    xdb << { :text => "once upon a time", :title => "A story" }
    xdb.flush
    xdb.size.should == 1
  end
end
