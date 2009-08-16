#!/usr/bin/ruby
#
# Example file spider using XapianFu.  Overwrites the index on each run (./spider.db)
#
# spider.rb /path/to/index

require 'rubygems'
require 'benchmark'
require 'lib/xapian_fu'

db = XapianFu::XapianDb.new(:dir => 'spider.db', :store => [:filename, :filesize],
                            :overwrite => true)

base_path = ARGV[0] || '.'

index_queue = [base_path]
total_file_count = 0
indexing_time = 0.0
STDERR.write "Indexing\n"
while dir = index_queue.shift
  STDERR.write " - #{dir}: "
  file_count = 0
  file_data = 0
  Dir.foreach(dir) do |filename|
    # skip . and ..
    next if filename =~ /^[.]{1,2}$/
    filename = File.join(dir, filename)
    # Put any directories we find onto the queue for indexing
    if File.directory?(filename)
      index_queue << filename
      next
    end
    next unless File.file?(filename)
    next unless filename =~ /(txt|doc|README|c|h|pl|sh|rb|py|note|xml)$/i
    file_count += 1

    # Read the first 10k of data
    text = File.open(filename) { |f| f.read(10 * 1024) }
    file_data += text.size
    # Index the data, filename and filesize
    bm = Benchmark.measure do
      db << {
        :text => text,
        :filename => filename,
        :filesize => File.size(filename)
      }
    end
    indexing_time += bm.real
  end
  STDERR.write("#{file_data / 1024}k in #{file_count} files\n")
  total_file_count += file_count
end

files_per_second = (total_file_count / indexing_time).round
puts "#{total_file_count} files indexed in #{indexing_time.round} seconds (#{files_per_second} per second)"
flush_time = Benchmark.measure { db.flush }.real
puts "Flush to disk took #{flush_time.round} seconds"
