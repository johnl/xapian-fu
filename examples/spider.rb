#!/usr/bin/ruby

require 'rubygems'
require 'benchmark'
require 'lib/xapian_fu'

db = XapianDb.new(:dir => 'spider.db', :overwrite => true)

base_path = ARGV[0] || '.'

docs = 0
indexing_time = 0.0
Dir.glob(File.join(base_path, "/**/*")) do |filename|
    next unless File.file?(filename)
    next unless filename =~ /\.(txt|doc|README|c|h|rb|py|note|xml)$/i
    puts "Indexing #{filename}"
    text = File.open(filename) { |f| f.read(10 * 1024) }
    bm = Benchmark.measure do
      db << XapianDoc.new({:text => text}, :data => { :filename => filename, :filesize => File.size(filename) })
    end
    indexing_time += bm.total
    docs += 1
    break if docs == 1000
end
indexing_time += Benchmark.measure { db.flush }.total
puts "#{docs} docs indexed in #{indexing_time} seconds (#{docs / indexing_time} docs per second)"
