require 'rubygems'
require 'bundler'
Bundler::GemHelper.install_tasks
require 'rspec/core/rake_task'
require 'rdoc/task'

task :default => :spec

desc "Run all specs in spec directory"
RSpec::Core::RakeTask.new do |t|
end

RDoc::Task.new('rdoc') do |t|
  t.rdoc_files.include('README.rdoc', 'lib/**/*.rb')
  t.main = 'README.rdoc'
  t.title = "XapianFu Documentation"
end
