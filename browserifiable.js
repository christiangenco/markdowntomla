// browserify -t coffeeify browserifiable.js > markdowntomla.js

window.markdowntomla     = require('./markdowntomla.coffee');
window.md                = require('markdown').markdown;
window._                 = require('underscore');
window.extractMetadata   = markdowntomla.extractMetadata;
window.createMLADocument = markdowntomla.createMLADocument;
window.blobStream        = require('blob-stream');