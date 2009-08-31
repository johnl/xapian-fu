require 'spec/rake/spectask'

desc "Run all specs in spec directory"
Spec::Rake::SpecTask.new do |t| 
  t.spec_opts = ['--options', "\"spec/spec.opts\""]
  t.spec_files = FileList['spec/*_spec.rb']
end
