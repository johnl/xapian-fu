Gem::Specification.new do |s|
  s.name    = 'xapian-fu'
  s.version = '1.1.1'
  s.date    = '2010-04-21'
  s.rubyforge_project = "xapian-fu"
  
  s.summary = "A Ruby interface to the Xapian search engine"
  s.description = "A library to provide a more Ruby-like interface to the Xapian search engine."
  
  s.authors  = ['John Leach']
  s.email    = 'john@johnleach.co.uk'
  s.homepage = 'http://github.com/johnl/xapian-fu/tree/master'
  
  s.has_rdoc = true

  s.files = Dir.glob("lib/**/*") + Dir.glob("examples/**/*")
  s.test_files = Dir.glob("spec/**/*")

  s.rdoc_options << '--title' << 'Xapian Fu' <<
    '--main' << 'README.rdoc' <<
    '--line-numbers'

  s.extra_rdoc_files = ["README.rdoc", "LICENSE"]

end
