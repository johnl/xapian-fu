require 'xapian'
require File.expand_path('../lib/xapian_fu.rb', File.dirname(__FILE__))
include XapianFu
require 'fileutils'
require 'date'

# Will be deleted
tmp_dir = '/tmp/xapian_fu_test.db'

describe XapianDb do
  before do
    FileUtils.rm_rf tmp_dir if File.exists?(tmp_dir)
  end

  describe "new" do
    it "should make an in-memory database by default" do
      xdb = XapianDb.new
      xdb.ro.should be_a_kind_of(Xapian::Database)
      xdb.rw.should === xdb.ro
    end

    it "should make an on-disk database when given a :dir option" do
      xdb = XapianDb.new(:dir => tmp_dir, :create => true)
      xdb.rw
      File.exists?(tmp_dir).should be_true
      xdb.should respond_to(:dir)
      xdb.dir.should == tmp_dir
      xdb.rw.should be_a_kind_of(Xapian::WritableDatabase)
      xdb.ro.should be_a_kind_of(Xapian::Database)
    end

  end

  it "should lazily create the on-disk database when rw is used" do
    xdb = XapianDb.new(:dir => tmp_dir, :create => true)
    File.exists?(tmp_dir).should be_false
    xdb.rw
    File.exists?(tmp_dir).should be_true
  end

  it "should flush documents to the index when flush is called" do
    xdb = XapianDb.new(:dir => tmp_dir, :create => true)
    xdb.flush
    xdb.size.should == 0
    xdb << "Once upon a time"
    xdb.size.should == 0
    xdb.flush
    xdb.size.should == 1
  end

  it "should return a nice string when inspect is called" do
    XapianDb.new.inspect.should =~ /XapianDb/
  end

  describe "transaction" do
    it "should commit writes when the block completed successfully" do
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
  end

  describe "documents" do

    it "should return a new XapianDoc with the db set on new" do
      xdb = XapianDb.new
      doc = xdb.documents.new
      doc.should be_a_kind_of XapianDoc
      doc.db.should == xdb
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

    it "should set the db field for the retrieved XapianDoc" do
      xdb = XapianDb.new
      xdb << "once upon a time"
      xdb.documents[1].db.should == xdb
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

    it "should handle being asked to delete docs that don't exist in the db" do
      xdb = XapianDb.new
      doc = xdb << XapianDoc.new("Once upon a time")
      xdb.flush
      xdb.documents.delete(100000).should == nil
    end

    describe "max" do
      it "should return the doc with the highest id" do
        xdb = XapianDb.new
        xdb << { :id => 20 }
        xdb << { :id => 9 }
        xdb << { :id => 15 }
        xdb.flush
        xdb.documents.max.id.should == 20
      end

      it "should return the doc with the highest specified stored value" do
        xdb = XapianDb.new(:fields => { :number => { :store => true } })
        xdb << { :id => 8, :number => "200" }
        xdb << { :id => 9, :number => "300" }
        xdb << { :id => 15, :number => "100"  }
        xdb.flush
        xdb.documents.max(:number).id.should == 9
      end
    end
  end

  describe "when indexing" do
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

    it "should generate boolean terms for multiple values" do
      xdb = XapianDb.new(:dir => tmp_dir, :create => true,
                         :fields => {
                           :name => { :index => true },
                           :colors => { :boolean => true }
                         }
                        )

      xdb << {:name => "Foo", :colors => [:red, :black]}
      xdb << {:name => "Foo", :colors => [:red, :green]}
      xdb << {:name => "Foo", :colors => [:blue, :yellow]}

      xdb.flush

      xdb.search("foo", :filter => {:colors => [:red]}).map(&:id).should == [1, 2]
      xdb.search("foo", :filter => {:colors => [:black, :green]}).map(&:id).should == [1, 2]

      xdb.search("red").should be_empty
    end

    it "should index boolean terms if asked to" do
      xdb = XapianDb.new(:dir => tmp_dir, :create => true,
                         :fields => {
                           :name   => { :index => true },
                           :colors => { :index => true, :boolean => true }
                         }
                        )

      xdb << {:name => "Foo", :colors => [:red, :black]}
      xdb << {:name => "Foo", :colors => [:red, :green]}
      xdb << {:name => "Foo", :colors => [:blue, :yellow]}

      xdb.flush

      xdb.search("foo", :filter => {:colors => [:red]}).map(&:id).should == [1, 2]
      xdb.search("foo", :filter => {:colors => [:black, :green]}).map(&:id).should == [1, 2]

      xdb.search("red").map(&:id).should == [1, 2]
    end

  end

  describe "search" do
    it "should return a list of XapianDocs with the weight and match set" do
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

    it "should collapse results by the value specified by the :collapse option" do
      xdb = XapianDb.new(:collapsible => :group)
      alpha1 = xdb << XapianDoc.new(:words => "cow dog cat", :group => "alpha")
      alpha2 = xdb << XapianDoc.new(:words => "cow dog", :group => "alpha")
      beta1  = xdb << XapianDoc.new(:words => "cow", :group => "beta")
      results = xdb.search("cow dog cat", :collapse => :group, :default_op => :or)
      results.should == [alpha1, beta1]
    end

    it "should do a case-insensitive boolean AND search by default" do
      xdb = XapianDb.new
      doc1 = xdb << "cow dog cat"
      doc2 = xdb << "cow dog"
      xdb.search("cow dog cat").should == [doc1]
    end

    it "should do a case-sensitive boolean search when the :boolean_anycase option is set to false" do
      pending
      xdb = XapianDb.new
      doc1 = xdb << "cow dog"
      doc2 = xdb << "COW dog"
      xdb.search("cow", :boolean_anycase => false).should == [doc1]
      xdb.search("COW", :boolean_anycase => false).should == [doc2]
    end

    it "should allow LOVEHATE style queries by default" do
      xdb = XapianDb.new
      doc1 = xdb << "cow dog cat moose"
      doc2 = xdb << "cow dog"
      doc3 = xdb << "cow dog moose"
      doc4 = xdb << "cow moose"
      xdb.search("cow +dog -cat", :default_op => :or).should == [doc2, doc3]
    end

    it "should do a boolean OR search when :default_op option is set to :or" do
      xdb = XapianDb.new
      doc1 = xdb << "cow dog cat"
      doc2 = xdb << "cow dog"
      xdb.search("cow dog cat", :default_op => :or).should == [doc1, doc2]
    end

    it "should allow a wildcard search by default" do
      xdb = XapianDb.new
      doc1 = xdb << "fox"
      doc2 = xdb << "follow"
      doc3 = xdb << "fantastic"
      xdb.search("fo*").should == [doc1, doc2]
    end

    it "should ignore wildcard searches when the :wildcards option is false" do
      xdb = XapianDb.new
      doc1 = xdb << "fox"
      doc2 = xdb << "follow"
      doc3 = xdb << "fo"
      xdb.search("fo*", :wildcards => false).should == [doc3]
    end

    it "should provide a corrected spelling string by default" do
      xdb = XapianDb.new(:dir => tmp_dir + 'corrected_spelling', :create => true,
                         :overwrite => true)
      xdb << "there is a mouse in this building"
      xdb.flush
      results = xdb.search("there was a moose at our building")
      results.corrected_query.should == "there was a mouse at our building"
    end

    it "should not provide corrected spellings when disabled" do
      xdb = XapianDb.new(:dir => tmp_dir + 'no_corrected_spelling', :create => true,
                         :overwrite => true, :spelling => false)
      xdb << "there is a mouse in this house"
      xdb.flush
      results = xdb.search("there was a moose at our house")
      results.corrected_query.should == ""
    end

    it "should do phrase matching when the :phrase option is set" do
      xdb = XapianDb.new
      doc1 = xdb << "the dog growls at the guitar"
      doc2 = xdb << "the cat growls at the dog"
      xdb.search('"the dog growls"').should == [doc1, doc2]
      xdb.search('"the dog growls"', :phrase => true).should == [doc1]
    end

    it "should do phrase matching on fields" do
      xdb = XapianDb.new(:fields => [:title])
      doc1 = xdb << { :title => "the dog growls", :body => "at the guitar" }
      doc2 = xdb << { :title => "the cat growls", :body => "at the dog" }
      xdb.search('title:"the dog growls"', :phrase => true).should == [doc1]
      xdb.search('title:"at the guitar"', :phrase => true).should == []
    end


    it "should do phrase matching by default when then :default_op option is :phrase" do
      pending
    end

    it "should do AND_MAYBE matching by default when the :default_op option is :and_maybe" do
      pending
    end

    it "should do PURE_NOT matching by default when the :default_op option is :pure_not" do
      pending
    end

    it "should page results when given the :page and :per_page options" do
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

    it "should return an array that can be used with will_paginate" do
      xdb = XapianDb.new
      content = "word"
      30.times { xdb << XapianDoc.new(content) }
      xdb.size.should == 30
      results = xdb.search(content, :page => 1, :per_page => 16)
      results.should be_a_kind_of XapianFu::ResultSet
      results.per_page.should == 16
      results.current_page.should == 1
      results.total_entries.should == 30
      results.total_pages.should == 2
      results.previous_page.should == nil
      results.next_page.should == 2
      results.offset.should == 0
      results = xdb.search(content, :page => 2, :per_page => 16)
      results.current_page.should == 2
      results.previous_page.should == 1
      results.next_page.should == nil
      results.offset.should == 16
    end

    it "should do searches with and without field names" do
      xdb = XapianDb.new(:fields => [:name, :partner])
      john = xdb << { :name => "John", :partner => "Louisa" }
      katherine = xdb << { :name => "Katherine", :partner => "John" }
      louisa = xdb << { :name => "Louisa", :partner => "John" }
      xdb.search("name:john").should == [john]
      xdb.search("partner:john").should == [katherine, louisa]
      xdb.search("partner:louisa").should == [john]
      xdb.search("louisa").should == [john,louisa]
      xdb.search("john").should == [john,katherine,louisa]
      xdb.search("john -name:john").should == [katherine,louisa]
    end

    it "should recognize synonyms" do
      xdb = XapianDb.new(:dir => tmp_dir + 'synonyms', :create => true,
                         :fields => [:name], :overwrite => true)

      xdb << {:name => "john"}
      xdb.flush

      xdb.search("jon", :synonyms => true).should be_empty

      xdb.add_synonym("jon", "john")
      xdb.flush

      xdb.search("jon").should be_empty
      xdb.search("jon", :synonyms => true).should_not be_empty
    end

    describe "special queries" do
      before do
        @xdb = XapianDb.new
        @xdb << "Doc 1"
        @xdb << "Doc 2"
      end

      it "should return empty array on MatchNothing" do
        @xdb.search(Xapian::Query::MatchNothing).should be_empty
      end

      it "should return all documents on MatchAll" do
        @xdb.search(Xapian::Query::MatchAll).length.should eq 2
      end
    end

    it "should allow to search by boolean terms" do
      xdb = XapianDb.new(:dir => tmp_dir, :create => true,
                         :fields => {
                           :name => { :index => true },
                           :age => { :boolean => true },
                           :city => { :boolean => true }
                         }
                        )

      xdb << {:name => "John A", :age => 10, :city => "London"}
      xdb << {:name => "John B", :age => 11, :city => "Liverpool"}
      xdb << {:name => "John C", :age => 12, :city => "Liverpool"}

      xdb.flush

      xdb.search("john").size.should == 3
      xdb.search("john", :filter => {:age => 10}).map(&:id).should == [1]
      xdb.search("john", :filter => {:age => [10, 12]}).map(&:id).should == [1, 3]

      xdb.search("john", :filter => {:age => 10, :city => "Liverpool"}).map(&:id).should == []
      xdb.search("john", :filter => {:city => "Liverpool"}).map(&:id).should == [2, 3]
      xdb.search("john", :filter => {:age => 11..15, :city => "Liverpool"}).map(&:id).should == [2, 3]

      xdb.search("liverpool").should be_empty
      xdb.search("city:liverpool").map(&:id).should == [2, 3]
    end
  end

  describe "filtering" do
    before do
      @xdb = XapianDb.new(
        :dir => tmp_dir, :create => true, :overwrite => true,
        :fields => {
          :name      => { :index => true },
          :age       => { :type => Integer, :sortable => true },
          :height    => { :type => Float, :sortable => true }
        }
      )
    end

    it "should filter results using value ranges" do
      @xdb << {:name => "John",   :age => 30, :height => 1.8}
      @xdb << {:name => "John",   :age => 35, :height => 1.9}
      @xdb << {:name => "John",   :age => 40, :height => 1.7}
      @xdb << {:name => "Markus", :age => 35, :height => 1.7}
      @xdb.flush

      # Make sure we're combining queries using OP_FILTER by comparing
      # the weights with and without filtering.
      @xdb.search("markus")[0].weight.should == @xdb.search("markus", :filter => {:age => "35"})[0].weight

      @xdb.search("john", :filter => {:age => "10..20"}).should be_empty

      @xdb.search("john", :filter => {:age => "10..30"}).map(&:id).should == [1]
      @xdb.search("john", :filter => {:age => "35.."}).map(&:id).should == [2, 3]
      @xdb.search("john", :filter => {:age => "..35"}).map(&:id).should == [1, 2]
      @xdb.search("john", :filter => {:age => ["..30", "40.."]}).map(&:id).should == [1, 3]

      @xdb.search("john", :filter => {:age => "10..30", :height => "1.8"}).map(&:id).should == [1]
      @xdb.search("john", :filter => {:age => "10..30", :height => "..1.8"}).map(&:id).should == [1]
      @xdb.search("john", :filter => {:age => "10..30", :height => "1.9.."}).should be_empty
    end
  end

  describe "add_doc" do
    it "should return a XapianDoc with an id" do
      xdb = XapianDb.new
      doc = XapianDoc.new("once upon a time")
      doc.id.should == nil
      new_doc = xdb << doc
      new_doc.id.should == 1
    end

    it "should add new docs with the given id" do
      xdb = XapianDb.new
      doc = xdb << XapianDoc.new(:id => 0xbeef, :title => "Once upon a time")
      xdb.documents[0xbeef].id.should == 0xbeef
      doc.id.should == 0xbeef
    end

    it "should replace docs that already have an id when adding to the db" do
      xdb = XapianDb.new
      doc = xdb << XapianDoc.new("Once upon a time")
      xdb.size.should == 1
      doc.id.should == 1
      updated_doc = xdb << doc
      xdb.size.should == 1
      updated_doc.id.should == doc.id
    end

    it "should store no fields by default" do
      xdb = XapianDb.new
      xdb << XapianDoc.new(:title => "Once upon a time")
      xdb.flush
      xdb.documents.find(1).values[:title].should be_empty
    end

    it "should store fields declared to be stored as values" do
      xdb = XapianDb.new(:fields => { :title => { :store => true } })
      xdb << XapianDoc.new(:title => "Once upon a time", :author => "Jim Jones")
      doc = xdb.documents.find(1)
      doc.values[:title].should == "Once upon a time"
      doc.values[:author].should be_empty
    end

    it "should store values declared as to be sortable" do
      xdb = XapianDb.new(:sortable => :age)
      xdb << XapianDoc.new(:age => "32", :author => "Jim Jones")
      doc = xdb.documents.find(1)
      doc.values.fetch(:age).should == "32"
    end

    it "should allow range searches on sortable values with prefixes" do
      xdb = XapianDb.new(:fields => { :price => { :type => Integer, :sortable => true, :range_prefix => "$" } })

      xdb << XapianDoc.new(:price => 10)
      xdb << XapianDoc.new(:price => 20)
      xdb << XapianDoc.new(:price => 15)

      docs = xdb.search("$10..15")

      docs.map { |d| d.id }.should == [1, 3]
    end

    it "should allow range searches on sortable values with postfixes" do
      xdb = XapianDb.new(:fields => { :age => { :type => Integer, :sortable => true, :range_postfix => "y" } })

      xdb << XapianDoc.new(:age => 32)
      xdb << XapianDoc.new(:age => 40)
      xdb << XapianDoc.new(:age => 35)

      docs = xdb.search("32..35y")

      docs.map { |d| d.id }.should == [1, 3]
    end

    it "should allow range queries without prefixes" do
      xdb = XapianDb.new(:fields => {
        :price => { :type => Integer, :sortable => true, :range_prefix => "$" },
        :age => { :type => Integer, :sortable => true }
      })

      xdb << XapianDoc.new(:price => 10, :age => 40)
      xdb << XapianDoc.new(:price => 20, :age => 35)
      xdb << XapianDoc.new(:price => 45, :age => 30)

      docs = xdb.search("$20..40 OR age:40..50")

      docs.map { |d| d.id }.should == [1, 2]
    end

    it "should store values declared as to be collapsible" do
      xdb = XapianDb.new(:collapsible => :group_id)
      xdb << XapianDoc.new(:group_id => "666", :author => "Jim Jones")
      doc = xdb.documents.find(1)
      doc.values.fetch(:group_id).should == "666"
    end

    it "should store data in the database" do
      xdb = XapianDb.new
      xdb << XapianDoc.new({ :text => "once upon a time" }, :data => Marshal::dump({ :thing => 0xdeadbeef }))
      xdb.size.should == 1
      doc = xdb.documents[1]
      Marshal::load(doc.data).should == { :thing => 0xdeadbeef }
    end
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
      results = @xdb.search("cow dog cat", :default_op => :or)
      results.should == @expected_results.sort_by { |r| r.fields[:relevance] }.reverse
    end

    it "should be by the value specified in descending numerical order" do
      results = @xdb.search("cow dog cat", :default_op => :or, :order => :number)
      results.should == @expected_results.sort_by { |r| r.fields[:number] }
    end

    it "should be reversed when the reverse option is set to true" do
      results = @xdb.search("cow dog cat", :default_op => :or, :order => :number, :reverse => true)
      results.should == @expected_results.sort_by { |r| r.fields[:number] }.reverse
    end

    it "should be by the id when specified and in ascending numerical order by default" do
      results = @xdb.search("cow dog cat", :default_op => :or, :order => :id)
      results.should == @expected_results.sort_by { |r| r.id }
    end

    it "should be by the id in descending numerical order when specified" do
      results = @xdb.search("cow dog cat", :default_op => :or, :order => :id, :reverse => true)
      results.should == @expected_results.sort_by { |r| r.id }.reverse
    end

  end

  describe "stemmer" do
    it "should return an english stemmer by default" do
      xdb = XapianDb.new
      xdb.stemmer.call("fishing").should == "fish"
      xdb.stemmer.call("contournait").should == "contournait"
    end
    it "should return a stemmer for the database language" do
      xdb = XapianDb.new(:language => :french)
      xdb.stemmer.call("contournait").should == "contourn"
      xdb.stemmer.call("fishing").should == "fishing"
    end
  end

  describe "stopper" do
    it "should return an english stopper by default" do
      xdb = XapianDb.new
      xdb.stopper.call("and").should == true
      xdb.stopper.call("avec").should == false
    end
    it "should return a stopper for the database language" do
      xdb = XapianDb.new(:language => :french)
      xdb.stopper.call("avec").should == true
      xdb.stopper.call("and").should == false
    end
  end

  describe "fields" do
    it "should return a hash of field names set as an array with the :fields option using String as the default type" do
      xdb = XapianDb.new(:fields => [:name, :age])
      xdb.fields[:name].should == String
      xdb.fields[:age].should == String
    end

    it "should return a hash of field names set as a hash with the :fields option" do
      xdb = XapianDb.new(:fields => { :name => String, :gender => String,
                           :age => { :type => Fixnum } })
      xdb.fields[:name].should == String
      xdb.fields[:gender].should == String
      xdb.fields[:age].should == Fixnum
    end

    it "should return an empty array by default" do
      XapianDb.new.fields.keys.should be_empty
    end

  end

  describe "stored_values" do
    it "should return an array of field names passed in the :store option" do
      xdb = XapianDb.new(:store => [:name, :title])
      xdb.store_values.should == [:name, :title]
    end

    it "should return an array of fields defined as storable in the :fields option" do
      xdb = XapianDb.new(:fields => {
                           :name => { :store => true },
                           :title => { :store => true } })
      xdb.store_values.should include :name
      xdb.store_values.should include :title
    end

    it "should return an array of fields both passed in the :store option and defined as storable in the :fields option" do
      xdb = XapianDb.new(:fields => {
                           :name => { :store => true },
                           :title => { :store => true } }, :store => [:name, :gender])
      xdb.store_values.size == 3
      [:gender, :title, :name].each { |f| xdb.store_values.should include f }
    end
  end

  describe "unindexed_fields" do
    it "should return an empty array by default" do
      xdb = XapianDb.new(:fields => { :name => String, :title => String })
      xdb.unindexed_fields.should == []
    end

    it "should return fields defined as not indexed in the fields option" do
      xdb = XapianDb.new(:fields => {
                           :name => { :type => String, :index => false },
                           :title => String })
      xdb.unindexed_fields.should include :name
      xdb.unindexed_fields.should_not include :title
    end
  end

end

