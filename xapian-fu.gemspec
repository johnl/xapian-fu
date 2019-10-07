$:.push File.expand_path('../lib', __FILE__)
require 'xapian_fu/version'

Gem::Specification.new do |s|
  s.name    = 'xapian-fu'
  s.version = XapianFu::VERSION
  s.date    = '2019-10-07'
  s.license = 'MIT'
  s.summary = "A Ruby interface to the Xapian search engine"
  s.description = "A library to provide a more Ruby-like interface to the Xapian search engine."

  s.authors  = ['John Leach', 'Damian Janowski']
  s.email    = 'john@johnleach.co.uk'
  s.homepage = 'https://github.com/johnl/xapian-fu'

  s.files = Dir.glob("lib/**/*") + Dir.glob("examples/**/*")
  s.test_files = Dir.glob("spec/**/*")
  s.require_paths = ["lib"]

  s.rdoc_options << '--title' << 'Xapian Fu' <<
    '--main' << 'README.rdoc' <<
    '--line-numbers'

  s.extra_rdoc_files = ["README.rdoc", "LICENSE", "CHANGELOG.rdoc"]

  s.add_development_dependency("rspec", "~> 2.7")
  s.add_development_dependency("rake", "~> 0")
  s.add_development_dependency("rdoc", "~> 4")

  s.requirements << "libxapian-dev, or the xapian-ruby gem"
  s.required_ruby_version = '>= 1.9.3'
end
