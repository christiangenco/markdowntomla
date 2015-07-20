require 'uglifier'

task default: %w[build]

task :build_mla do
  puts "browserifying"
  puts system("browserify -t coffeeify browser.app.coffee > js/markdowntomla.js")

  puts "building minified self-contained index.html"
  html = File.read('template.html')
  bundled = html.split("\n").map{|line|
    if line =~ /\<script.*src=\"(.*)\"/
      path = $1
      js = Uglifier.compile(File.read(path))
      "<script type='text/javascript'>#{js}</script>"
    else
      line
    end
  }
  File.open('built/index.html', 'w'){|f| f.puts bundled}
end

task :build_apa do
  puts "browserifying"
  puts system("browserify -t coffeeify browser.markdowntoapa.coffee > js/markdowntoapa.js")

  puts "building minified self-contained index.html"
  html = File.read('template_markdowntoapa.html')
  bundled = html.split("\n").map{|line|
    if line =~ /\<script.*src=\"(.*)\"/
      path = $1
      js = Uglifier.compile(File.read(path))
      "<script type='text/javascript'>#{js}</script>"
    else
      line
    end
  }
  File.open('built/apa/index.html', 'w'){|f| f.puts bundled}
end