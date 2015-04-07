_           = require 'underscore'
md          = require('markdown').markdown
coffee      = require 'coffee-script'
PDFDocument = require 'pdfkit'

Array::first ?= -> @[0]

Array::last ?= -> @[@length - 1]

process.chdir(__dirname)

# style definitions for markdown
styles =
  default:
    font: 'Times-Roman'
    fontSize: 12
    lineGap: 14
    align: 'left'
  meta:
    indent: 0
  title:
    align: 'center'
  para:
    indent: 72/2
  blockquote:
    indent: 0
    marginLeft: 72
    color: 'red'
    font: 'Times-Italic'
  em:
    font: 'Times-Italic'
  strong:
    font: 'Times-Bold'
  h1:
    align: 'center'
    font: 'Times-Bold'
  h2:
    font: 'Times-Bold'
  h3:
    font: 'Times-Bold'
    inline: true
    indent: 72/2
  # h4:
  #   font: 'Times-Italic'
  #   align: 'center'
  # h5:
  #   underline: true
  citationHeader:
    align: 'center'
  citation:
    indent: -72/2
    marginLeft: 72/2

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

    switch @type
      when 'header'
        @type = 'h' + @attrs.level
      when 'img'
        # images are used to generate inline example output
        # compiles the coffeescript to JS so it can be run
        # in the render method
        @type = 'example'
        code = codeBlocks[@attrs.alt]
        @code = coffee.compile code if code
        @height = +@attrs.title or 0

    @style = _.extend({}, styles.default, styles[@type])

    # parse sub nodes
    @content = while tree.length
      child = new Node tree.shift()
      # blockquotes have an embedded paragraph; make sure the inner paragraph doesn't re-define
      # its indentation
      child.style?.indent = @style.indent if @style.indent?
      child

    # console.log "content =", @content
    # console.log "type =", @type


  # sets the styles on the document for this node
  setStyle: (doc) ->
    if @style.font
      doc.font @style.font

    if @style.fontSize
      doc.fontSize @style.fontSize

    if @style.color
      doc.fillColor @style.color
    else
      doc.fillColor 'black'

  # renders this node and its subnodes to the document
  render: (doc, continued = false) ->
    # console.log "rendering node: ", @
    if @style.marginLeft
      doc.x += @style.marginLeft

    switch @type
      when 'hr'
        doc.addPage()
      else
        # loop through subnodes and render them
        for fragment, index in @content
          if fragment.type is 'text'
            @setStyle doc

            # remove newlines unless this is code
            # unless @type is 'code'
            #   fragment.text = fragment.text.replace(/[\r\n]\s*/g, ' ')

            # console.log "rendering text. continued =", continued, 'attrs.continued =', @attrs.continued
            text = fragment.text
            text = text + " " if @style.inline
            doc.text text, _.extend({}, @style, {continued: continued or index < @content.length - 1 or @style.inline})
          else
            # console.log "rendering fragment #{fragment.type}"
            fragment.render doc, index < @content.length - 1 and @type isnt 'bulletlist'

    if @style.marginBottom
      doc.y += @style.marginBottom
    if @style.marginLeft
      doc.x -= @style.marginLeft

addAPAHeader = (doc, runningHead) ->
  range = doc.bufferedPageRange() # => { start: 0, count: 2 }
  doc.font styles.default.font
  for i in [range.start...range.start + range.count]
    doc.switchToPage(i)
    doc.y = 72/2
    doc.x = 72
    head = runningHead
    head = "Running head: " + head if i == 0
    doc.text head, _.extend({}, styles.default, {})

    doc.y = 72/2
    doc.x = 72
    doc.text "#{i + 1}", _.extend({}, styles.default, {align: 'right'})

# reads and renders a markdown/literate coffeescript file to the document
render = (doc, tree) ->
  doc.font 'Times-Roman'
  doc.fontSize 12

  codeBlocks = []

  onWorksCited = false
  while tree.length
    node = new Node(tree.shift())
    # console.log "node =", node
    if node.type == "h1" && node.content?.first()?.text?.toLowerCase() == "references"
      onWorksCited = true
      node.style = _.extend({}, styles.default, styles.citationHeader)

    if onWorksCited && node.type == "para"
      node.style = _.extend({}, styles.default, styles.citation)

    node.render(doc)

  doc

# renders the title page of the guide
# renderTitlePage = (doc) ->
#   title = 'PDFKit Guide'
#   author = 'By Devon Govett'
#   version = 'Version ' + require('./package.json').version

#   doc.font 'fonts/AlegreyaSans-Light.ttf', 60
#   doc.y = doc.page.height / 2 - doc.currentLineHeight()
#   doc.text title, align: 'center'
#   w = doc.widthOfString(title)

#   doc.fontSize 20
#   doc.y -= 10
#   doc.text author,
#     align: 'center'
#     indent: w - doc.widthOfString(author)

#   doc.font styles.para.font, 10
#   doc.text version,
#     align: 'center'
#     indent: w - doc.widthOfString(version)

#   doc.addPage()

extractMetadata = (text) ->
  body = ""
  metadata = {}

  metadata_pattern = /// ^
    ([\w.-]+) # key
    \:\       # colon
    \s*       # optional whitespace
    (.+)      # value
  $///

  for line in text.split("\n")
    if meta = line.match(metadata_pattern)
      key = meta[1]
      value = meta[2].replace(/\\n/, "\n")
      metadata[key] = value
    else
      body += line + "\n"

  {metadata: metadata, body: body}

createAPADocument = (body, metadata, stream) ->
  tree = md.parse body
  tree.shift() # ignore 'markdown' first element

  metadata.lastName ||= metadata.author?.split(" ").last()

  doc = new PDFDocument
    bufferPages: true

  doc.info.Title    = metadata.title.replace("\n", " ")
  doc.info.Author   = metadata.author
  doc.info.Creator = "markdowntoapa by christian.gen.co"

  # add header
  doc.y = 72*3
  doc.font 'Times-Roman'
  doc.fontSize 12
  doc.text(metadata.title,       _.extend({}, styles.default, styles.title))
  doc.text(metadata.author,      _.extend({}, styles.default, styles.title))
  doc.text(metadata.institution, _.extend({}, styles.default, styles.title))

  doc.addPage()

  # add abstract page
  doc.text("Abstract", _.extend({}, styles.default, styles.citationHeader))
  doc.text(metadata.abstract, _.extend({}, styles.default, {}))
  if metadata.keywords
    # TODO: more generic text writing function
    doc.font styles.em.font
    doc.text("Keywords: ", _.extend({continued: true}, styles.default, styles.para))
    doc.font styles.default.font
    doc.text(metadata.keywords, _.extend({}, styles.default, styles.para))

  doc.addPage()

  doc.text(metadata.title,       _.extend({}, styles.default, styles.title))

  render doc, tree
  addAPAHeader(doc, metadata.runninghead)
  doc.end()
  doc

exports.extractMetadata   = extractMetadata
exports.createAPADocument = createAPADocument

do ->
  # command line
  fs = require 'fs'
  filename = "apa_paper.md"
  content  = fs.readFileSync(filename, 'utf8')
  content  = extractMetadata(content)
  body     = content.body
  metadata = content.metadata
  doc      = createAPADocument(body, metadata)
  stream   = fs.createWriteStream("#{metadata.title.replace("\n", ' ')} by #{metadata.author}.pdf")
  doc.pipe(stream)