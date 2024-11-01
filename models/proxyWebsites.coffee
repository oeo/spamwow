# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ L, log } = require './../lib/logger'
{ env, exit } = process

{ mongoose, redis } = require './../lib/database'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

helpers = require './../lib/helpers'
path = require 'path'
{ fork } = require 'child_process'
http = require 'http'

_ = require 'lodash'
AWS = require 'aws-sdk'

# constants
PROXY_SCRIPT = path.resolve(__dirname, '../bin/proxy-website.coffee')
REDIS_PROXY_PREFIX = 'proxy:process:'

# available port range for proxies 
try
  PORT_RANGE = env.PROXY_PORT_RANGE.split('-').map(Number)
catch error
  PORT_RANGE = [20000, 30000]

modelOpts = {
  name: 'ProxyWebsite'
  schema: {
    collection: 'proxywebsites'
    strict: true 
  }
}

StringReplacementSchema = new Schema {
  find: String
  replace: String
}, { _id: false }

ProxyWebsiteSchema = new Schema {

  isActive: { type: Boolean, default: true }

  port: {
    type: Number
    validate: (v) -> v >= PORT_RANGE[0] and v <= PORT_RANGE[1]
  }

  originalHost: {
    type: String
    required: true
    trim: true
  }

  trackingScripts: {
    type: [String]
    default: []
  }

  injectScriptHeader: {
    type: String
    default: ''
  }

  injectScriptFooter: {
    type: String
    default: ''
  }

  stringReplacements: {
    type: [StringReplacementSchema]
    default: []
  }

  # process tracking fields
  pid: { type: Number, default: null }
  isRunning: { type: Boolean, default: false }
  lastStarted: { type: Number, default: 0 }
  lastStopped: { type: Number, default: 0 }

  # health check fields
  isHealthy: { type: Boolean, default: false }
  timeHealthChecked: { type: Number, default: 0 }

}, modelOpts.schema

ProxyWebsiteSchema.plugin(basePlugin)

# auto-assign port if not specified
ProxyWebsiteSchema.pre 'save', (next) ->
  return next() if @port
  
  try
    docs = await @constructor.find({}, 'port').sort(port: 1)
    ports = []

    if docs
      ports = _.map docs, (x) -> +x.port
    
    # start with minimum port from range
    [minPort, maxPort] = PORT_RANGE

    for x in [minPort..maxPort]
      if x not in ports
        L 'Found available proxy port', x
        @port = x
        return next()

    return next new Error 'No available proxy port found in range'
  catch error
    return next error

# process management methods
ProxyWebsiteSchema.methods.start = (opt = {}) ->
  try
    L 'Starting proxy website', { _id: @_id, originalHost: @originalHost, port: @port }

    # check if already running
    if @isRunning and @pid
      processExists = await @_checkProcess()
      if processExists
        return { success: true, message: 'Proxy already running', pid: @pid }

    # fork the proxy process
    child = fork PROXY_SCRIPT, [],
      env: Object.assign {}, process.env,
        PROXY_WEBSITE_ID: @_id
        NODE_ENV: process.env.NODE_ENV
      stdio: 'inherit'
      detached: false # keep process attached to parent

    # store process info in redis for tracking
    await redis.hset "#{REDIS_PROXY_PREFIX}#{@_id}",
      pid: child.pid
      startTime: Date.now()
      port: @port

    # update model
    @pid = child.pid
    @isRunning = true
    @lastStarted = Date.now()
    await @save()

    # handle process exit
    child.on 'exit', (code, signal) =>
      @_handleProcessExit(code, signal)

    # handle process errors
    child.on 'error', (error) =>
      L.error 'Proxy process error', { _id: @_id, error: error.message }
      @_handleProcessExit(1, 'error')

    return { success: true, pid: child.pid }

  catch error
    L.error 'Error starting proxy', { _id: @_id, error: error.message }
    throw error

ProxyWebsiteSchema.methods.stop = (opt = {}) ->
  try
    if !@isRunning or !@pid
      return { success: true, message: 'Proxy not running' }

    # check if process exists
    processExists = await @_checkProcess()
    if !processExists
      await @_cleanup()
      return { success: true, message: 'Process already stopped' }

    L 'Stopping proxy website', { _id: @_id, originalHost: @originalHost, port: @port }

    # kill the process
    try
      process.kill(@pid)
      await @_cleanup()
      return { success: true, message: 'Proxy stopped' }
    catch error
      if error.code == 'ESRCH' # process doesn't exist
        await @_cleanup()
        return { success: true, message: 'Process already stopped' }
      throw error

  catch error
    L.error 'Error stopping proxy', { _id: @_id, error: error.message }
    throw error

ProxyWebsiteSchema.methods.restart = (opt = {}) ->
  try
    await @stop()
    return await @start()
  catch error
    L.error 'Error restarting proxy', { _id: @_id, error: error.message }
    throw error

ProxyWebsiteSchema.methods.checkHealth = (opt = {}) ->
  try
    L 'Checking health of proxy website', { _id: @_id, originalHost: @originalHost, port: @port }

    # check if process is running
    if @isRunning and @pid
      processExists = await @_checkProcess()
      if !processExists
        @isHealthy = false
        await @_cleanup()
      else
        # check if port is listening
        try
          await new Promise (resolve, reject) =>
            req = http.get "http://localhost:#{@port}/health",
              timeout: 5000
            req.on 'response', (res) ->
              if res.statusCode == 200
                resolve(true)
              else
                reject(new Error("Unhealthy status code: #{res.statusCode}"))
            req.on 'error', reject
            req.on 'timeout', -> reject(new Error('Health check timeout'))

          @isHealthy = true
        catch error
          @isHealthy = false
          L.error 'Health check failed', { _id: @_id, error: error.message }

    @timeHealthChecked = helpers.time() 
    await @save()

    return { success: true, isHealthy: @isHealthy }

  catch error
    L.error 'Error checking proxy health', { _id: @_id, error: error.message }
    throw error

# helper methods
ProxyWebsiteSchema.methods._checkProcess = ->
  try
    process.kill(@pid, 0)
    return true
  catch error
    return false

ProxyWebsiteSchema.methods._cleanup = ->
  try
    @isRunning = false
    @pid = null
    @lastStopped = Date.now()
    await @save()
    await redis.del "#{REDIS_PROXY_PREFIX}#{@_id}"
  catch error
    L.error 'Error cleaning up proxy data', { _id: @_id, error: error.message }

ProxyWebsiteSchema.methods._handleProcessExit = (code, signal) ->
  # L 'Proxy process exited', { _id: @_id, code, signal }
  @_cleanup()

# static methods for managing all proxies
ProxyWebsiteSchema.statics.listRunning = (opt = {}) ->
  try
    # L 'Listing running proxy websites'
    
    # get all processes from redis
    keys = await redis.keys "#{REDIS_PROXY_PREFIX}*"
    running = []

    for key in keys
      id = key.replace(REDIS_PROXY_PREFIX, '')
      info = await redis.hgetall(key)
      
      if info?.pid
        processExists = try
          process.kill(parseInt(info.pid), 0)
          true
        catch
          false

        if processExists
          proxy = await @findById(id)
          if proxy
            running.push
              _id: proxy._id
              originalHost: proxy.originalHost
              port: proxy.port
              pid: parseInt(info.pid)
              startTime: parseInt(info.startTime)
        else
          # clean up dead process
          await redis.del(key)
          proxy = await @findById(id)
          if proxy
            await proxy._cleanup()

    return running

  catch error
    L.error 'Error listing running proxies', error
    throw error

# start all active proxies
ProxyWebsiteSchema.statics.startAll = (opt = {}) ->
  try
    # L 'Starting all active proxy websites'
    proxies = await @find({ isActive: true })
    results = []
    
    for proxy in proxies
      try
        result = await proxy.start()
        results.push
          _id: proxy._id
          success: true
          pid: result.pid
      catch error
        results.push
          _id: proxy._id
          success: false
          error: error.message

    return results
  catch error
    L.error 'Error starting all proxies', error
    throw error

# stop all running proxies
ProxyWebsiteSchema.statics.stopAll = (opt = {}) ->
  try
    # L 'Stopping all proxy websites'
    proxies = await @find({ isRunning: true })
    results = []
    
    for proxy in proxies
      try
        await proxy.stop()
        results.push
          _id: proxy._id
          success: true
      catch error
        results.push
          _id: proxy._id
          success: false
          error: error.message

    return results
  catch error
    L.error 'Error stopping all proxies', error
    throw error

# middleware to handle process management on save
ProxyWebsiteSchema.pre 'save', (next) ->
  try
    if @isModified('isActive') or @isModified('port') or @isModified('originalHost')
      if @isActive
        await @restart()
      else
        await @stop()
  catch error
    return next(error)
  next()

# cleanup on model removal
ProxyWebsiteSchema.pre 'remove', (next) ->
  try
    await @stop()
  catch error
    return next(error)
  next()

# cleanup function for graceful shutdown
cleanup = ->
  try
    model = mongoose.model(modelOpts.name)
    proxies = await model.find({ isRunning: true })
    for proxy in proxies
      await proxy.stop()
    process.exit(0)
  catch error
    L.error 'Error during cleanup', error
    process.exit(1)

# register cleanup handlers
process.on 'SIGTERM', cleanup
process.on 'SIGINT', cleanup

# create and export the model
model = mongoose.model modelOpts.name, ProxyWebsiteSchema
module.exports = EXPOSE(model)