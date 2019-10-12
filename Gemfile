source "https://rubygems.org"

gemspec

group :test do
  if RUBY_VERSION < '2.1'
    gem "xapian-ruby", "~> 1.2.22"
  else
    gem "xapian-ruby", "~> 1.4.9"
  end
end
