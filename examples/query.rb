#!/usr/bin/ruby
#
require 'rubygems'
require 'benchmark'
require 'lib/xapian_fu'

query_string = ARGV.join(" ")
db = XapianFu::XapianDb.new(:dir => 'spider.db')
results = nil
bm = Benchmark.measure { results = db.search(query_string) }
puts "Weight\tFilename"
results.each do |result|
  puts "%.2f\t%s" % [result.weight, result.fields[:filename]]
end
puts "Search took %.5f seconds" %  bm.total

