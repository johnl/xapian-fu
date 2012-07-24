require File.expand_path('../lib/xapian_fu.rb', File.dirname(__FILE__))

tmp_dir = '/tmp/xapian_fu_test.db'

describe "Facets support" do

  before do
    FileUtils.rm_rf(tmp_dir)

    @xdb = XapianFu::XapianDb.new(
      :dir => tmp_dir, :create => true, :overwrite => true,
      :fields => {
        :name      => { :index => true },
        :age       => { :type => Integer, :sortable => true },
        :height    => { :type => Float, :sortable => true }
      }
    )

    @xdb << {:name => "John A",   :age => 30, :height => 1.8}
    @xdb << {:name => "John B",   :age => 35, :height => 1.8}
    @xdb << {:name => "John C",   :age => 40, :height => 1.7}
    @xdb << {:name => "John D",   :age => 40, :height => 1.7}
    @xdb << {:name => "Markus",   :age => 35, :height => 1.7}
    @xdb.flush
  end

  it "should expose facets when searching" do
    results = @xdb.search("john", {:facets => [:age, :height]})

    results.facets[:age].should == [[30, 1], [35, 1], [40, 2]]
    results.facets[:height].should == [[1.7, 2], [1.8, 2]]

    results.facets.keys.map(&:to_s).sort == %w(age height)
  end

  it "should allow to set the minimum amount of documents to check" do
    100.times do |i|
      @xdb << {:name => "John A #{i}", :age => 30, :height => 1.8}
      @xdb << {:name => "John B #{i}", :age => 35, :height => 1.8}
      @xdb << {:name => "John C #{i}", :age => 40, :height => 1.7}
      @xdb << {:name => "John D #{i}", :age => 40, :height => 1.7}
      @xdb << {:name => "Markus #{i}", :age => 35, :height => 1.7}
    end

    @xdb.flush

    results = @xdb.search("john", :facets => [:age, :height], :check_at_least => :all)

    results.facets[:age].map(&:last).inject(0) { |t,i| t + i }.should == 404

    results = @xdb.search(:all, :facets => [:age, :height], :check_at_least => :all)

    results.facets[:age].map(&:last).inject(0) { |t,i| t + i }.should == 505
  end
end
