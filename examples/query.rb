#!/usr/bin/ruby
#
# Example file spider index searcher using XapianFu. Conducts a search
# on ./spider.db created with spider.rb.
#
# --order-by-filesize sorts the results by the file size, largest
# first. Default is to sort by relevance.
#
# All other command line arguments are used as the search query:
#
# query.rb --order-by-filesize mammoth -woolley
#
# You can limit queries to particular fields:
#
# query.rb filename:LICENSE text:BSD
#
require 'rubygems'
require 'benchmark'
require 'lib/xapian_fu'

order = nil
reverse = false
if ARGV.delete('--order-by-filesize')
  order = :filesize
  reverse = true
end
query = ARGV.join(" ")
db = XapianFu::XapianDb.new(:dir => 'spider.db', :fields => [:text, :filesize, :filename])
puts "Xapian Database has #{db.size} docs in total"
puts "Largest filesize recorded is #{db.documents.max(:filesize).values[:filesize].to_i / 1024}k"
puts "Searching for '#{query}'"
results = nil
bm = Benchmark.measure do
  results = db.search(query, :order => order, :reverse => reverse)
end
puts "Returned #{results.size} of #{results.total_entries} total hits"
puts "Weight\tFilename\tFilesize"
results.each do |result|
  filename = result.values[:filename]
  filesize = result.values[:filesize].to_i / 1024
  puts "%.2f\t%s\t%ik" % [result.weight, filename, filesize]
end
puts "Search took %.5f seconds" %  bm.real

