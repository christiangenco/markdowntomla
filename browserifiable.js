// browserify -t coffeeify browserifiable.js > markdowntomla.js

window.md                = require('markdown').markdown;
markdowntomla            = require('./markdowntomla.coffee');
window.extractMetadata   = markdowntomla.extractMetadata;
window.createMLADocument = markdowntomla.createMLADocument;