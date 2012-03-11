require 'xapian'
require File.expand_path('../lib/xapian_fu.rb', File.dirname(__FILE__))
include XapianFu

describe QueryParser do
  describe "parse_query" do
    it "should use the database's stopper" do
      xdb = XapianDb.new(:stopper => :french)
      qp = QueryParser.new(:database => xdb)
      terms = qp.parse_query("avec and").terms.collect { |t| t.term }
      terms.should_not include "Zavec"
      terms.should include "Zand"
    end

    it "should use the database's stemmer" do
      xdb = XapianDb.new(:stemmer => :french)
      qp = QueryParser.new(:database => xdb)
      terms = qp.parse_query("contournait fishing").terms.collect { |t| t.term }
      terms.should include "Zcontourn"
      terms.should_not include "Zfish"
    end

    it "should use the :fields option to set field names" do
      qp = QueryParser.new(:fields => [:name, :age])
      terms = qp.parse_query("name:john age:30").terms.collect { |t| t.term }
      terms.should include "XNAMEjohn"
      terms.should_not include "john"
      terms.should include "XAGE30"
      terms.should_not include "30"
    end

    it "should use the database's field names as prefixes" do
      xdb = XapianDb.new(:fields => [:name], :stemmer => :none)
      qp = QueryParser.new(:database => xdb)
      terms = qp.parse_query("name:john").terms.collect { |t| t.term }
      terms.should include "XNAMEjohn"
      terms.should_not include "john"
    end

    it "should turn :all into a query with no terms" do
      qp = QueryParser.new
      qp.parse_query(:all).terms.should == []
      qp.parse_query(:all).empty?.should be_false
      qp.parse_query(:nothing).empty?.should be_true
    end

  end

end

