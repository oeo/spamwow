# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ env, process } = require 'process'
{ log, L } = require './logger'

cryptoLib = require './crypto'

memoryCache = require 'memory-cache'
Handlebars = require 'handlebars'

swag = require './vendor/swag'
swag.registerHelpers(Handlebars)

render = (templateString, data = {}) ->
  if memoryCache.get(cacheKey = cryptoLib.sha256(templateString))
    template = memoryCache.get(cacheKey)
  else
    template = Handlebars.compile(templateString)
    memoryCache.put(cacheKey, template)

  return template(data)

##
module.exports = render

if !module.parent
  log render "Hello, {{name}}!", {name: "World"}

  log render """
    {{#if 1}}
      Hello, {{default title 'notAvailable'}}!
    {{/if}}
    {{#each people}}
      {{name}}
    {{/each}}
  """, {people: [{name: "John"}, {name: "Jane"}]}

