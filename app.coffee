# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log, L } = require './lib/logger'
{ env, exit } = process

require './lib/env'

# log ascii art
fs = require 'fs'
packageData = require './package.json'

if fs.existsSync(artFile = './ascii.art')
  bulk = fs.readFileSync artFile, 'utf8'
  bulk = bulk.split('package.name').join(packageData.name)
  bulk = bulk.split('package.version').join(packageData.version)
  bulk = bulk.split('env').join(process.env.NODE_ENV)
  log bulk

_ = require 'lodash'

express = require 'express'
bodyParser = require 'body-parser'
compression = require 'compression'
cors = require 'cors'

middleware = require './lib/middleware'
coffeeQuery = require './lib/coffeeQuery'

app = express()
app.disable 'x-powered-by'

if env.SERVER_X_POWERED_BY
  app.use (req, res, next) ->
    res.header 'x-powered-by', env.SERVER_X_POWERED_BY
    next()

# handle path based on stage
if stage = env.STAGE
  app.use (req, res, next) ->
    if stage and req.url.indexOf("/#{stage}") is 0
      req.url = req.url.substring(stage.length + 1)
      if req.originalUrl.indexOf("/#{stage}") is 0
        req.originalUrl = req.originalUrl.substring(stage.length + 1)
    next()

app.use cors()
app.use compression()
app.use middleware.realIp
app.use middleware.methodOverride
app.use middleware.metadata
app.use middleware.respond
app.use bodyParser.json()
app.use bodyParser.urlencoded { extended: true }
app.use coffeeQuery.parseExtraFilters
app.use coffeeQuery.middleware

# expose models as rest
{ modelRouter } = require './lib/autoExpose'

for _k, model of (require './models')
  continue if !model.EXPOSE
  try
    router = modelRouter({ model })
    app.use model.EXPOSE.route, router
  catch e
    throw e

# expose some routes
# app.use '/public', require('./routes/public')

# catch errors
app.use (e,req,res,next) ->
  L.error e
  return res.respond e, 500

# 404
app.use (req,res,next) ->
  doIgnore = false

  for x in [
    'favicon'
    'robots.txt'
    'sitemap.xml'
  ]
    if req.url.includes(x)
      doIgnore = true
      break

  if !doIgnore
    L.debug '404', req.method.toLowerCase(), req.url

  return res.respond (new Error '404'), 404

module.exports = app

if !module.parent
  { ready } = require(__dirname + '/lib/database')

  await ready()

  # initialize proxy websites
  try
    { ProxyWebsites } = require './models'
    
    # stop any potentially running proxies first (cleanup)
    await ProxyWebsites.stopAll()
    
    # start all active proxies
    results = await ProxyWebsites.startAll()
    
    # log results
    for result in results
      if result.success
        L.log "Started proxy website", { _id: result._id, pid: result.pid }
      else
        L.error "Failed to start proxy website", { _id: result._id, error: result.error }

    # register cleanup on app shutdown
    process.on 'SIGTERM', ->
      await ProxyWebsites.stopAll()
      process.exit(0)

    process.on 'SIGINT', ->
      await ProxyWebsites.stopAll()
      process.exit(0)

  catch error
    L.error "Error initializing proxy websites:", error

  app.listen (localPort = env.LOCAL_PORT ? 8000), ->
    L.log "listening :#{localPort}"

