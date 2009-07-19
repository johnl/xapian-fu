require 'xapian'
require 'lib/xapian_fu.rb'
include XapianFu
require 'fileutils'

describe StopperFactory do
  describe "stopper_for" do
    it "should return a SimpleStopper loaded with the given languages stop words" do
      stopper = StopperFactory.stopper_for(:english)
      stopper.should be_a_kind_of Xapian::SimpleStopper
      stopper.call("and").should be_true
      stopper.call("theremin").should_not be_true
    end

    it "should return the given stopper unmodified if given a Xapian::Stopper object" do
      stopper = Xapian::SimpleStopper.new
      StopperFactory.stopper_for(stopper).should === stopper
    end
  end

  describe "stop_words_for" do

    it "should return an array of words for the given language" do
      words = StopperFactory.stop_words_for(:english)
      words.should be_a_kind_of Array
      words.should_not be_empty
      words.should include 'and'
      words.should include "they're"
    end

    it "should raise a UnsupportedStopperLanguage error if there is no data for the given language" do
      Proc.new { StopperFactory.stop_words_for(:no_existy) }.should raise_error UnsupportedStopperLanguage
    end

    it "should return an array with no empty strings, nils or pipes" do
      StopperFactory.stop_words_for(:english).should_not include ''
      StopperFactory.stop_words_for(:english).should_not include nil
      StopperFactory.stop_words_for(:english).should_not include '|'
    end

  end
end
