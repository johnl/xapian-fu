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

  describe "to_xapian_document" do
    it "should tokenize strings" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new("once upon a time").to_xapian_document
      xdoc.terms.should be_a_kind_of Array
      xdoc.terms.last.should be_a_kind_of Xapian::Term
      xdoc.terms.last.term.should == "upon"
    end

    it "should store positions by default when tokenizing" do
      xdb = XapianDb.new
      doc = xdb.documents.new("once upon a time")
      doc.save
      xdb.ro.positionlist(doc.id, "time").first.should == 4
    end

    it "should not store positions when tokenizing when :index_positions is set to false" do
      xdb = XapianDb.new(:index_positions => false)
      doc = xdb.documents.new("once upon a time")
      doc.save
      xdb.ro.positionlist(doc.id, "once").first.should == nil
    end

    it "should tokenize a hash" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new(:title => 'once upon a time').to_xapian_document
      xdoc.terms.should be_a_kind_of Array
      xdoc.terms.last.should be_a_kind_of Xapian::Term
      xdoc.terms.last.term.should == "upon"
    end

    it "should stem English words by default" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new("She fished for fish").to_xapian_document
      terms = xdoc.terms.collect { |t| t.term }
      terms.should_not include "Zfished"
      terms.should include "Zfish"
    end

    it "should inherit the databases stemmer by default" do
      xdb = XapianDb.new(:stemmer => :french)
      xdoc = xdb.documents.new("majestueusement").to_xapian_document
      xdoc.terms.first.term.should == 'Zmajestu'
    end

    stems = {
      :german => { "aufeinander" => "aufeinand" },
      :french => { "majestueusement" => "majestu" },
      :swedish => { "kloekornas" => "kloek" },
      :danish => { "indvendingerne" => "indvending" },
      :russian => { "падшую", "падш" },
      :italian => { "propagamento" => "propag" }
    }
    stems.keys.each do |lang|
      stems[lang].each do |word, stem|
        it "should stem #{lang.to_s.capitalize} words when the :stemmer option is set to :#{lang}" do
          xdb = XapianDb.new
          xdoc = xdb.documents.new(word, :stemmer => lang).to_xapian_document
          xdoc.terms.first.term.should == 'Z'+stem
        end
      end
    end

    it "should not stem words when stemmer is set to false" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new("She fished for fish", :stemmer => false).to_xapian_document
      terms = xdoc.terms.collect { |t| t.term if t.term =~ /^Z/ }.compact
      terms.should be_empty
    end
    
    it "should not stem english stop words by default" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new("And they made a cake", :stemmer => :english).to_xapian_document
      terms = xdoc.terms.collect { |t| t.term }
      terms.should_not include 'Zand'
      terms.should_not include 'Za'
      terms.should include 'Zcake'
    end
    
    it "should allow setting the stopper on initialisation" do
      xdb = XapianDb.new(:stopper => :english)
      xdoc = xdb.documents.new("And they made a cake", :stopper => :french)
      xdoc.stopper.call("ayantes").should == true
      xdoc.stopper.call("and").should == false
    end
    
    it "should support stop words encoded in utf8" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new("и они made a cake", :stemmer => :russian, :stopper => :russian).to_xapian_document
      terms = xdoc.terms.collect { |t| t.term }
      terms.should_not include 'Zи'
      terms.should_not include 'Zони'
      terms.should include 'Zcake'      
    end
  end

end
