require 'json'
require 'open-uri'

langs = %w(danish dutch english finnish french german hungarian italian norwegian portuguese spanish swedish)

stopwords = JSON.parse(URI.open("https://raw.githubusercontent.com/stopwords-iso/stopwords-iso/refs/heads/master/stopwords-iso.json").read)


stopwords.each do |k, v|
  file = File.join(File.dirname(__FILE__), "#{k}.txt")
  File.open(file, "w") do |f|
    f.write v.join("\n")
  end
end
