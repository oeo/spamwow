# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log, L } = require './../lib/logger'
{ exit, env } = process

require './../lib/env'

{ mongoose, redis, connected } = require './../lib/database'

helpers = require './../lib/helpers'

_ = require 'lodash'

{
  ProxyWebsites
} = require './../models'

run = ->
  await connected()
  start = new Date

  # remove all proxy websites
  L 'Removing all proxy websites...'
  await ProxyWebsites.deleteMany({})

  doc = new ProxyWebsites({
    originalHost: 'https://thespectacledbean.com/'
    injectScriptHeader: ''
    injectScriptFooter: ''
    stringReplacements: [
      {
        find: 'THE SPECTACLED BEAN'
        replace: 'THE PROXIED BEAN'
      }
    ]
  })

  result = await doc.save()
  L 'Created proxy website', result

  doc = new ProxyWebsites({
    originalHost: 'https://blackmoonlilith.art.blog/'
    injectScriptHeader: ''
    injectScriptFooter: ''
    stringReplacements: [
      {
        find: 'Black Moon Lilith'
        replace: 'Black Moon Proxy'
      }
      {
        find: 'Musings of a Wandering Soul'
        replace: 'Website is Totally Owned'
      }
    ]
  })

  result = await doc.save()
  L 'Created proxy website', result

  return { elapsed: new Date() - start }

module.exports = {
  run
}

if !module.parent
  await run()
  exit 0

