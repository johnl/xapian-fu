require 'xapian'
require 'lib/xapian_fu.rb'

tmp_dir = '/tmp/xapian_fu_test.db'

describe XapianDb do

  it "should make an in-memory database by default" do
    xdb = XapianDb.new
    xdb.ro.should be_a_kind_of(Xapian::Database)
    xdb.rw.should === xdb.ro
  end
  
  it "should make an on-disk database when given a :dir option" do
    xdb = XapianDb.new(:dir => tmp_dir, :create => true)
    xdb.should respond_to(:dir)
    xdb.dir.should == tmp_dir
    xdb.rw.should be_a_kind_of(Xapian::WritableDatabase)
    xdb.ro.should be_a_kind_of(Xapian::Database)
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

  it "should index a string" do
    xdb = XapianDb.new
    xdb << "once upon a time"
    xdb.flush
    xdb.size.should == 1
  end

  it "should retrieve documents like an array and return a XapianDoc" do
    xdb = XapianDb.new
    xdb << "once upon a time"
    xdb.flush
    xdb.documents[1].should be_a_kind_of(XapianDoc)
  end

  it "should provide the id of retrieved documents" do
    xdb = XapianDb.new
    xdb << "once upton a time"
    xdb.flush
    xdb.documents[1].id.should == 1
  end

  it "should store data in the database" do
    xdb = XapianDb.new
    xdb << XapianDoc.new({ :text => "once upon a time" }, :data => { :thing => 0xdeadbeef })
    xdb.flush
    xdb.size.should == 1
    doc = xdb.documents[1]
    doc.data.should == { :thing => 0xdeadbeef }
  end

end
