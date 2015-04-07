require 'uglifier'

task default: %w[build]

task :build do
  # puts system("browserify -t coffeeify browser.app.coffee > js/markdowntomla.js")
  html = File.read('index.html')
  bundled = html.split("\n").map{|line|
    if line =~ /\<script.*src=\"(.*)\"/
      path = $1
      js = Uglifier.compile(File.read(path))
      "<script type='text/javascript'>#{js}</script>"
    else
      line
    end
  }
  File.open('index.min.html', 'w'){|f| f.puts bundled}
end