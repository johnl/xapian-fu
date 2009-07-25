langs = %w(danish dutch english finnish french german hungarian italian norwegian portuguese spanish swedish)

langs.each { |l| system("curl http://snowball.tartarus.org/algorithms/%s/stop.txt | iconv -f ISO-8859-1 -t utf8 > %s.txt" % [l, l]) }

system("curl http://snowball.tartarus.org/algorithms/russian/stop.txt | iconv -f KOI8-R -t utf8 > russian.txt")


