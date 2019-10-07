#!/usr/bin/env ruby
#

require 'date'
require 'xapian_fu'
include XapianFu
require_relative 'fixtures/film_data'
require 'fileutils'


db_name = [RUBY_PLATFORM, RUBY_VERSION].join('~')
db_path = File.join(File.dirname(__FILE__), 'fixtures/film_data')
FileUtils.mkdir_p db_path
db = XapianDb.new(:dir => File.join(db_path, db_name), :create => true,
									:fields => {
															:title => { :type => String, :store => true }, 
															:released_on => { :type => Date, :store => true }, 
															:revenue => { :type => Integer, :store => true }})



FILM_DATA.each { |film| db << film }


