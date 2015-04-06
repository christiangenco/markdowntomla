fs = require 'fs'
_ = require 'underscore'
vm = require 'vm'
md = require('markdown').markdown
coffee = require 'coffee-script'
CodeMirror = require 'codemirror/addon/runmode/runmode.node'
PDFDocument = require 'pdfkit'

Array::first ?= -> @[0]

Array::last ?= -> @[@length - 1]

process.chdir(__dirname)

# setup code mirror coffeescript mode
filename = require.resolve('codemirror/mode/coffeescript/coffeescript')
coffeeMode = fs.readFileSync filename, 'utf8'
vm.runInNewContext coffeeMode, CodeMirror: CodeMirror

# style definitions for markdown
styles =
  # h1:
  #   font: 'Times-Roman'
  #   fontSize: 25
  #   padding: 15
  # h2:
  #   font: 'Times-Roman'
  #   fontSize: 18
  #   padding: 10
  # h3:
  #   font: 'Times-Roman'
  #   fontSize: 18
  #   padding: 10
  meta:
    font: 'Times-Roman'
    fontSize: 12
    lineGap: 24
    align: 'left'
    indent: 0
  title:
    font: 'Times-Roman'
    fontSize: 12
    lineGap: 24
    align: 'center'
  para:
    font: 'Times-Roman'
    fontSize: 12
    lineGap: 24
    align: 'left'
    indent: 72
    # padding: 10
  # code:
  #   font: 'Times-Roman'
  #   fontSize: 9
  # code_block:
  #   padding: 10
  #   background: '#2c2c2c'
  # inlinecode:
  #   font: 'Times-Roman'
  #   fontSize: 10
  # listitem:
  #   font: 'Times-Roman'
  #   fontSize: 10
  #   padding: 6
  # link:
  #   font: 'Times-Roman'
  #   fontSize: 10
  #   color: 'blue'
  #   underline: true
  # example:
  #   font: 'Times-Roman'
  #   fontSize: 9
  #   color: 'black'
  #   padding: 10
  em:
    font: 'Times-Italic'
    align: 'left'
  strong:
    font: 'Times-Bold'
    align: 'left'
  # u:
  #   underline: true

# syntax highlighting colors
# based on Github's theme
colors =
  keyword: '#cb4b16'
  atom: '#d33682'
  number: '#009999'
  def: '#2aa198'
  variable: '#108888'
  'variable-2': '#b58900'
  'variable-3': '#6c71c4'
  property: '#2aa198'
  operator: '#6c71c4'
  comment: '#999988'
  string: '#dd1144'
  'string-2': '#009926'
  meta: '#768E04'
  qualifier: '#b58900'
  builtin: '#d33682'
  bracket: '#cb4b16'
  tag: '#93a1a1'
  attribute: '#2aa198'
  header: '#586e75'
  quote: '#93a1a1'
  link: '#93a1a1'
  special: '#6c71c4'
  default: '#002b36'

codeBlocks = []
lastType = null

# This class represents a node in the markdown tree, and can render it to pdf
class Node
  constructor: (tree) ->
    # special case for text nodes
    if typeof tree is 'string'
      @type = 'text'
      @text = tree
      return

    @type = tree.shift()
    @attrs = {}

    if typeof tree[0] is 'object' and not Array.isArray tree[0]
      @attrs = tree.shift()

    # parse sub nodes
    @content = while tree.length
      new Node tree.shift()

    switch @type
      when 'header'
        @type = 'h' + @attrs.level

      when 'code_block'
        # use code mirror to syntax highlight the code block
        code = @content[0].text
        @content = []
        CodeMirror.runMode code, 'coffeescript', (text, style) =>
          color = colors[style] or colors.default
          opts =
            color: color
            continued: text isnt '\n'

          @content.push new Node ['code', opts, text]

        @content[@content.length - 1]?.attrs.continued = false
        codeBlocks.push code

      when 'img'
        # images are used to generate inline example output
        # compiles the coffeescript to JS so it can be run
        # in the render method
        @type = 'example'
        code = codeBlocks[@attrs.alt]
        @code = coffee.compile code if code
        @height = +@attrs.title or 0

    @style = styles[@type] or styles.para

  # sets the styles on the document for this node
  setStyle: (doc) ->
    if @style.font
      doc.font @style.font

    if @style.fontSize
      doc.fontSize @style.fontSize

    if @style.color or @attrs.color
      doc.fillColor @style.color or @attrs.color
    else
      doc.fillColor 'black'

    options = {}
    options.lineGap = @style.lineGap || 24
    options.align = @style.align
    options.indent = @style.indent
    # options.paragraphGap = 24
    options.link  = @attrs.href or false # override continued link
    options.continued = @attrs.continued if @attrs.continued?
    return options

  # renders this node and its subnodes to the document
  render: (doc, continued = false) ->
    switch @type
      when 'example'
        @setStyle doc

        # translate all points in the example code to
        # the current point in the document
        doc.moveDown()
        doc.save()
        doc.translate(doc.x, doc.y)
        x = doc.x
        y = doc.y
        doc.x = doc.y = 0

        # run the example code with the document
        vm.runInNewContext @code,
          doc: doc
          lorem: lorem

        # restore points and styles
        y += doc.y
        doc.restore()
        doc.x = x
        doc.y = y + @height
      when 'hr'
        doc.addPage()
      else
        # loop through subnodes and render them
        for fragment, index in @content
          if fragment.type is 'text'
            # add a new page for each heading, unless it follows another heading
            if @type in ['h1', 'h2'] and lastType? and lastType isnt 'h1'
              doc.addPage()

            # set styles and whether this fragment is continued (for rich text wrapping)
            options = @setStyle doc
            options.continued ?= continued or index < @content.length - 1

            # remove newlines unless this is code
            unless @type is 'code'
              fragment.text = fragment.text.replace(/[\r\n]\s*/g, ' ')

            doc.text fragment.text, options
          else
            fragment.render doc, index < @content.length - 1 and @type isnt 'bulletlist'

          lastType = @type

    if @style.padding
      doc.y += @style.padding

# reads and renders a markdown/literate coffeescript file to the document
render = (doc, filename) ->
  doc.font 'Times-Roman'
  doc.fontSize 12

  codeBlocks = []
  content = fs.readFileSync(filename, 'utf8')

  body = ""

  metadata_pattern = /// ^
    ([\w.-]+) # key
    \:\       # colon
    \s*       # optional whitespace
    (.+)      # value
  $///

  metadata = {}

  for line in content.split("\n")
    if meta = line.match(metadata_pattern)
      key = meta[1]
      value = meta[2]
      metadata[key] = value
    else
      body += line

  metadata.lastName ||= metadata.author?.split(" ").last()
  # console.log metadata

  # add header
  doc.text(metadata.author, styles.meta)
  doc.text(metadata.instructor, styles.meta)
  doc.text(metadata.course, styles.meta)
  doc.text(metadata.date, styles.meta)
  doc.text(metadata.title, styles.title)

  tree = md.parse body
  tree.shift()

  while tree.length
    node = new Node tree.shift()
    node.render(doc)

  # add page numbers
  range = doc.bufferedPageRange() # => { start: 0, count: 2 }

  for i in [range.start...range.start + range.count]
    doc.switchToPage(i)
    doc.y = 72/2
    doc.x = 72
    doc.text "#{metadata.lastName} #{i + 1}",
      align: 'right'

  doc.flushPages()
  doc

# renders the title page of the guide
renderTitlePage = (doc) ->
  title = 'PDFKit Guide'
  author = 'By Devon Govett'
  version = 'Version ' + require('./package.json').version

  doc.font 'fonts/AlegreyaSans-Light.ttf', 60
  doc.y = doc.page.height / 2 - doc.currentLineHeight()
  doc.text title, align: 'center'
  w = doc.widthOfString(title)

  doc.fontSize 20
  doc.y -= 10
  doc.text author,
    align: 'center'
    indent: w - doc.widthOfString(author)

  doc.font styles.para.font, 10
  doc.text version,
    align: 'center'
    indent: w - doc.widthOfString(version)

  doc.addPage()

renderHeader = (doc) ->

do ->
  doc = new PDFDocument
    bufferPages: true

  doc.pipe fs.createWriteStream('guide.pdf')
  render doc, 'test.coffee.md'

  doc.end()
