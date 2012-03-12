# encoding: utf-8
require 'xapian'
require File.expand_path('../lib/xapian_fu.rb', File.dirname(__FILE__))
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
      xdb.ro.positionlist(doc.id, "time").first.should_not == nil
    end

    it "should not store positions when tokenizing when :index_positions is set to false" do
      xdb = XapianDb.new(:index_positions => false)
      doc = xdb.documents.new("once upon a time")
      doc.save
      xdb.ro.positionlist(doc.id, "once").first.should == nil
    end

    it "should tokenize an array given as a field" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new(:colors => [:red, :green, :blue]).to_xapian_document
      xdoc.terms.should be_a_kind_of Array
      xdoc.terms.last.should be_a_kind_of Xapian::Term
      terms = xdoc.terms.collect { |t| t.term }
      terms.should include "red"
      terms.should include "green"
      terms.should include "blue"
      terms.should_not include "redgreenblue"
    end

    it "should tokenize an array given as the content" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new([:red, :green, :blue]).to_xapian_document
      xdoc.terms.should be_a_kind_of Array
      xdoc.terms.last.should be_a_kind_of Xapian::Term
      terms = xdoc.terms.collect { |t| t.term }
      terms.should include "red"
      terms.should include "green"
      terms.should include "blue"
      terms.should_not include "redgreenblue"
    end

    it "should tokenize a hash" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new(:title => 'once upon a time').to_xapian_document
      xdoc.terms.should be_a_kind_of Array
      xdoc.terms.last.should be_a_kind_of Xapian::Term
      xdoc.terms.last.term.should == "upon"
    end

    it "should tokenize the fields of a hash separately" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new({ :text => "once upon a time", :title => "A story" }).to_xapian_document
      terms = xdoc.terms.collect { |t| t.term }
      terms.should include "XTEXTonce"
      terms.should include "XTITLEstory"
      terms.should_not include "XTEXTstory"
    end

    it "should not tokenize fields declared as not to be indexed" do
      xdb = XapianDb.new(:fields => { :name => { :index => false } })
      xdoc = xdb.documents.new({ :name => 'John Leach', :quote => 'Xapian Rocks' }).to_xapian_document
      terms = xdoc.terms.collect { |t| t.term }
      terms.should_not include 'XNAMEjohn'
      terms.should_not include 'XNAMEleach'
      terms.should_not include 'Zjohn'
      terms.should_not include 'Zleach'
      terms.should_not include 'john'
      terms.should_not include 'leach'
    end

    it "should convert Time instances to a useful format when tokenizing" do
      time = Time.now
      xdb = XapianDb.new
      xdoc = xdb.documents.new(:created_at => time).to_xapian_document
      terms = xdoc.terms.collect { |t| t.term }
      terms.should include time.utc.strftime("%Y%m%d%H%M%S")
    end

    it "should convert DateTime instances to a useful format when tokenizing" do
      datetime = DateTime.now
      xdb = XapianDb.new
      xdoc = xdb.documents.new(:created_at => datetime).to_xapian_document
      terms = xdoc.terms.collect { |t| t.term }
      terms.should include datetime.strftime("%Y%m%d%H%M%S")
    end

    it "should convert Time instances to a useful format when tokenizing" do
      date = Date.today
      xdb = XapianDb.new
      xdoc = xdb.documents.new(:created_on => date).to_xapian_document
      terms = xdoc.terms.collect { |t| t.term }
      terms.should include date.strftime("%Y%m%d")
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
      terms = xdoc.terms.collect { |t| t.term }
      terms.should include 'Zmajestu'
    end

    stems = {
      :german => { "aufeinander" => "aufeinand" },
      :french => { "majestueusement" => "majestu" },
      :swedish => { "kloekornas" => "kloek" },
      :danish => { "indvendingerne" => "indvending" },
      :russian => { "падшую" => "падш" },
      :italian => { "propagamento" => "propag" }
    }
    stems.keys.each do |lang|
      stems[lang].each do |word, stem|
        it "should stem #{lang.to_s.capitalize} words when the :stemmer option is set to :#{lang}" do
          xdb = XapianDb.new
          xdoc = xdb.documents.new(word, :stemmer => lang).to_xapian_document
          terms = xdoc.terms.collect { |t| t.term.respond_to?(:force_encoding) ? t.term.force_encoding("UTF-8") : t.term }
          terms.should include 'Z' + stem
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

    it "should not stop words when stopper is set to false" do
      xdb = XapianDb.new
      xdoc = xdb.documents.new("And they made a cake", :stopper => false).to_xapian_document
      terms = xdoc.terms.collect { |t| t.term }
      terms.should include 'and'
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

  describe "stemmer" do
    it "should return the same stemmer as the database by default" do
      xdb = XapianDb.new(:language => :french)
      xdoc = xdb.documents.new("stink and bones")
      xdoc.stemmer.call("contournait").should == "contourn"
    end
    it "should return a stemmer for the document language, overriding the db" do
      xdb = XapianDb.new(:language => :english)
      xdoc = xdb.documents.new("stink and bones", :language => :french)
      xdoc.stemmer.call("contournait").should == "contourn"
    end
    it "should return a stemmer set by the :stemmer option, overriding the :language option and the db stemmer" do
      xdb = XapianDb.new(:language => :german)
      xdoc = xdb.documents.new("stink and bones", :language => :english, :stemmer => :french)
      xdoc.stemmer.call("contournait").should == "contourn"
    end

  end

  describe "stopper" do
    it "should return the same stopper as the database by default" do
      xdb = XapianDb.new(:language => :french)
      xdoc = xdb.documents.new("stink and bones")
      xdoc.stopper.call("avec").should == true
    end
    it "should return a stopper for the document language, overriding the db" do
      xdb = XapianDb.new(:language => :english)
      xdoc = xdb.documents.new("stink and bones", :language => :french)
      xdoc.stopper.call("avec").should == true
    end
    it "should return a stopper set by the :stopper option, overriding the :language option and the db stopper" do
      xdb = XapianDb.new(:language => :german)
      xdoc = xdb.documents.new("stink and bones", :language => :english, :stopper => :french)
      xdoc.stopper.call("avec").should == true
    end
  end

end
