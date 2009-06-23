require 'xapian'
require 'lib/xapian_fu.rb'
include XapianFu
require 'fileutils'

# Will be deleted
tmp_dir = '/tmp/xapian_fu_test.db'

describe XapianDb do
  before do
    FileUtils.rm_rf tmp_dir if File.exists?(tmp_dir)
  end
    
  it "should make an in-memory database by default" do
    xdb = XapianDb.new
    xdb.ro.should be_a_kind_of(Xapian::Database)
    xdb.rw.should === xdb.ro
  end
  
  it "should make an on-disk database when given a :dir option" do
    xdb = XapianDb.new(:dir => tmp_dir, :create => true)
    File.exists?(tmp_dir).should be_true
    xdb.should respond_to(:dir)
    xdb.dir.should == tmp_dir
    xdb.rw.should be_a_kind_of(Xapian::WritableDatabase)
    xdb.ro.should be_a_kind_of(Xapian::Database)
  end

  it "should flush documents to the index when flush is called" do
    xdb = XapianDb.new(:dir => tmp_dir, :create => true)
    xdb.size.should == 0
    xdb << "Once upon a time"
    xdb.size.should == 0
    xdb.flush
    xdb.size.should == 1
  end

  it "should support transactions" do
    xdb = XapianDb.new(:dir => tmp_dir, :create => true)
    xdb << "Once upon a time"
    xdb.transaction do
      xdb << "Once upon a time"
      xdb.size.should == 1
    end
    xdb.flush
    xdb.size.should == 2
  end

  it "should serialize attempts at concurrent transactions" do
    xdb = XapianDb.new(:dir => tmp_dir, :create => true)
    thread = Thread.new do
      xdb.transaction do
        sleep 0.1
        xdb << "Once upon a time"
        sleep 0.1
        xdb << "Once upon a time"
      end
    end
    xdb.transaction do
      xdb << "Once upon a time"
      sleep 0.1
      xdb << "Once upon a time"
    end
    thread.join
    xdb.flush
    xdb.size.should == 4
  end

  it "should abort a transaction on an exception" do
    xdb = XapianDb.new(:dir => tmp_dir, :create => true)
    xdb << "Once upon a time"
    begin
      xdb.transaction do
        xdb << "Once upon a time"
        raise StandardError
      end
    rescue StandardError
    end
    xdb.flush
    xdb.size.should == 1
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
    xdb.size.should == 1
    xdb << XapianDoc.new("once upon a time")
    xdb.size.should == 2
  end

  it "should raise a XapianFu::DocNotFound error on find if the document doesn't exist" do
    xdb = XapianDb.new
    xdb << "once upon a time"
    xdb.flush
    lambda { xdb.documents.find(10) }.should raise_error XapianFu::DocNotFound
  end

  it "should retrieve documents with the find method" do
    xdb = XapianDb.new
    xdb << "Once upon a time"
    xdb.flush
    xdb.documents.find(1).should be_a_kind_of(XapianDoc)
  end

  it "should retrieve documents like an array and return a XapianDoc" do
    xdb = XapianDb.new
    xdb << "once upon a time"
    xdb.flush
    xdb.documents[1].should be_a_kind_of(XapianDoc)
  end

  it "should provide the id of retrieved documents" do
    xdb = XapianDb.new
    xdb << "once upon a time"
    xdb.documents[1].id.should == 1
  end

  it "should store data in the database" do
    xdb = XapianDb.new
    xdb << XapianDoc.new({ :text => "once upon a time" }, :data => { :thing => 0xdeadbeef })
    xdb.size.should == 1
    doc = xdb.documents[1]
    doc.data.should == { :thing => 0xdeadbeef }
  end

  it "should return a XapianDoc with an id after indexing" do
    xdb = XapianDb.new
    doc = XapianDoc.new("once upon a time")
    doc.id.should == nil
    new_doc = xdb << doc
    new_doc.id.should == 1
  end

  it "should replace docs that already have an id when adding to the db" do
    xdb = XapianDb.new
    doc = xdb << XapianDoc.new("Once upon a time")
    xdb.flush
    xdb.size.should == 1
    doc.id.should == 1
    updated_doc = xdb << doc
    xdb.flush
    xdb.size.should == 1
    updated_doc.id.should == doc.id
  end

  it "should delete docs by id" do
    xdb = XapianDb.new
    doc = xdb << XapianDoc.new("Once upon a time")
    xdb.flush
    xdb.size.should == 1
    xdb.documents.delete(doc.id).should == 1
    xdb.flush
    xdb.size.should == 0
  end
  
  it "should return the doc with the highest id with the max method" do
    xdb = XapianDb.new
    xdb << { :id => 20 }
    xdb << { :id => 9 }
    xdb << { :id => 15 }
    xdb.flush
    xdb.documents.max.id.should == 20
  end

  it "should return the doc with the highest specified value with the max method" do
    xdb = XapianDb.new(:sortable => :number)
    xdb << { :id => 8, :number => "200" }
    xdb << { :id => 9, :number => "300" }
    xdb << { :id => 15, :number => "100"  }
    xdb.flush
    xdb.documents.max(:number).id.should == 9
  end

  it "should handle being asked to delete docs that don't exist in the db" do
    xdb = XapianDb.new
    doc = xdb << XapianDoc.new("Once upon a time")
    xdb.flush
    xdb.documents.delete(100000).should == nil
  end

  it "should add new docs with the given id" do
    xdb = XapianDb.new
    doc = xdb << XapianDoc.new(:id => 0xbeef, :title => "Once upon a time")
    xdb.flush
    xdb.documents[0xbeef].id.should == 0xbeef
    doc.id.should == 0xbeef
  end

  it "should tokenize strings" do
    xdb = XapianDb.new
    doc = xdb << XapianDoc.new("once upon a time")
    doc.terms.should be_a_kind_of Array
    doc.terms.last.should be_a_kind_of Xapian::Term
    doc.terms.last.term.should == "upon"
  end

  it "should tokenize a hash" do
    xdb = XapianDb.new
    doc = xdb << XapianDoc.new(:title => 'once upon a time')
    doc.terms.should be_a_kind_of Array
    doc.terms.last.should be_a_kind_of Xapian::Term
    doc.terms.last.term.should == "upon"
  end

  it "should return a list of XapianDocs with the weight and match set when returning search results" do
    xdb = XapianDb.new
    xdb << XapianDoc.new(:title => 'once upon a time')
    xdb << XapianDoc.new(:title => 'three little pings')
    results = xdb.search("pings")
    results.should be_a_kind_of Array
    results.size.should == 1
    results.first.should be_a_kind_of XapianDoc
    results.first.match.should be_a_kind_of Xapian::Match
    results.first.weight.should be_a_kind_of Float
  end

  it "should support searching with :page and :per_page options" do
    xdb = XapianDb.new
    content = "word"
    200.times { xdb << XapianDoc.new(content) }
    xdb.size.should == 200
    results = xdb.search(content, :page => 1, :per_page => 12)
    results.first.id.should == 1
    results.size.should == 12
    results = xdb.search(content, :page => 5, :per_page => 18)
    results.first.id.should == 18 * 4 + 1
    results.size.should == 18
    results = xdb.search(content, :page => 100, :per_page => 12)
    results.size.should == 0
  end
  
  it "should limit results when the :limit option is given" do
    xdb = XapianDb.new
    content = "word"
    30.times { xdb << XapianDoc.new(content) }
    xdb.size.should == 30
    results = xdb.search(content, :limit => 16)
    results.size.should == 16
  end

  it "should store no fields by default" do
    xdb = XapianDb.new
    xdb << XapianDoc.new(:title => "Once upon a time")
    xdb.flush
    xdb.documents.find(1).fields[:title].should be_nil
  end

  it "should store fields declared as to be stored" do
    xdb = XapianDb.new(:store => :title)
    xdb << XapianDoc.new(:title => "Once upon a time", :author => "Jim Jones")
    xdb.flush
    doc = xdb.documents.find(1)
    doc.fields[:title].should == "Once upon a time"
    doc.fields[:author].should be_nil
  end
  
  it "should store values declared as to be sortable" do
    xdb = XapianDb.new(:sortable => :age)
    xdb << XapianDoc.new(:age => "32", :author => "Jim Jones")
    xdb.flush
    doc = xdb.documents.find(1)
    doc.get_value(:age).should == "32"
  end

  it "should store time objects in a string sortable order when storing as values" do
    xdb = XapianDb.new(:sortable => :created_at)
    time = Time.now
    xdb << XapianDoc.new(:created_at => time, :title => "Teaching a Ferret to dance")
    xdb.flush
    doc = xdb.documents.find(1)
    doc.get_value(:created_at).should == time.utc.strftime("%Y%m%d%H%M%S")
  end
  
  it "should store integers in a string sortable order when storing as values" do
    xdb = XapianDb.new(:sortable => :number)
    xdb << XapianDoc.new(:number => 57, :title => "Teaching a Ferret to dance")
    xdb.flush
    doc = xdb.documents.find(1)
    doc.get_value(:number).should == "%.10d" % 57
  end
  
  it "should store values declared as to be collapsible" do
    xdb = XapianDb.new(:collapsible => :group_id)
    xdb << XapianDoc.new(:group_id => "666", :author => "Jim Jones")
    xdb.flush
    doc = xdb.documents.find(1)
    doc.get_value(:group_id).should == "666"
  end

  describe "search results sort order" do
    before(:each) do
      @xdb = XapianDb.new(:sortable => :number)
      @expected_results = []
      @expected_results << (@xdb << XapianDoc.new(:words => "cow dog", :number => 3, :relevance => 2))
      @expected_results << (@xdb << XapianDoc.new(:words => "cow dog cat", :number => 1, :relevance => 3))
      @expected_results << (@xdb << XapianDoc.new(:words => "cow", :number => 2, :relevance => 1))
    end
    
    it "should be by search result weight by default" do
      results = @xdb.search("cow dog cat")
      results.should == @expected_results.sort_by { |r| r.fields[:relevance] }.reverse
    end
    
    it "should be by the value specified in descending numerical order" do
      results = @xdb.search("cow dog cat", :order => :number)
      results.should == @expected_results.sort_by { |r| r.fields[:number] }
    end
    
    it "should be reversed when the reverse option is set to true" do
      results = @xdb.search("cow dog cat", :order => :number, :reverse => true)
      results.should == @expected_results.sort_by { |r| r.fields[:number] }.reverse
    end
    
    it "should be by the id when specified and in ascending numerical order by default" do
      results = @xdb.search("cow dog cat", :order => :id)
      results.should == @expected_results.sort_by { |r| r.id }
    end
    
    it "should be by the id in descending numerical order when specified" do
      results = @xdb.search("cow dog cat", :order => :id, :reverse => true)
      results.should == @expected_results.sort_by { |r| r.id }.reverse      
    end
    
  end
  
  it "should collapse results by the value specified by the :collapse option" do
    xdb = XapianDb.new(:collapsible => :group)
    alpha1 = xdb << XapianDoc.new(:words => "cow dog cat", :group => "alpha")
    alpha2 = xdb << XapianDoc.new(:words => "cow dog", :group => "alpha")
    beta1  = xdb << XapianDoc.new(:words => "cow", :group => "beta")
    results = xdb.search("cow dog cat", :collapse => :group)
    results.should == [alpha1, beta1]
  end
  
end
