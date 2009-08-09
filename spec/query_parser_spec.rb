require 'xapian'
require 'lib/xapian_fu.rb'
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
  end

end

