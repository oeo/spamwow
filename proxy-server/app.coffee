# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
http = require('http')
https = require('https')
yaml = require('js-yaml')
fs = require('fs')
path = require('path')
{ URL } = require('url')
zlib = require('zlib')
Redis = require('ioredis')
winston = require('winston')
express = require('express')
IP2Location = require('ip2location-nodejs').IP2Location
require('winston-daily-rotate-file')
customRoutes = require('./routes')
cloakFn = require('./cloak')

# Constants
CACHE_TTL = 1800  # 30 minutes in seconds
DEFAULT_REQUEST_TIMEOUT = 5000  # 5 seconds in ms

# Custom pretty logging format
logFormat = winston.format.printf (info) ->
  timestamp = info.timestamp
  level = info.level.toUpperCase().padEnd(7)
  if typeof info.message is 'object'
    message = JSON.stringify(info.message, null, 2)
  else
    message = info.message
  return "#{timestamp} [#{level}] #{message}"

# Setup logger with rotation
setupLogger = (config) ->
  logDir = config.settings?.log_dir or './logs'
  fs.mkdirSync(logDir, recursive: true) unless fs.existsSync(logDir)

  logger = winston.createLogger
    level: config.settings?.log_level or 'info'
    format: winston.format.combine(
      winston.format.timestamp(format: 'YYYY-MM-DD HH:mm:ss')
      winston.format.colorize()
      logFormat
    )
    transports: [
      new winston.transports.Console()
      new winston.transports.DailyRotateFile
        filename: path.join(logDir, 'proxy-%DATE%.log')
        datePattern: 'YYYY-MM-DD'
        maxSize: config.settings?.log_size_limit or '10m'
        maxFiles: '14d'
        format: winston.format.combine(
          winston.format.timestamp(format: 'YYYY-MM-DD HH:mm:ss')
          winston.format.uncolorize()
          logFormat
        )
    ]

  return logger

class RateLimiter
  constructor: (@capacity, @fillRate) ->
    @tokens = @capacity
    @lastFill = Date.now()

  tryAcquire: ->
    now = Date.now()
    timePassed = now - @lastFill
    @tokens = Math.min(@capacity, @tokens + timePassed * (@fillRate / 1000))
    @lastFill = now

    if @tokens >= 1
      @tokens -= 1
      return true
    return false

class ProxyService
  constructor: (@config, @logger) ->
    @sites = new Map()
    @ip2location = null

    # Initialize GeoIP
    try
      dbPath = path.join(__dirname, 'geoip', 'IP2LOCATION-LITE-DB1.BIN')
      if fs.existsSync(dbPath)
        @ip2location = new IP2Location()
        @ip2location.open(dbPath)
        @logger.info "IP2Location database loaded successfully"
      else
        @logger.warn "IP2Location database not found. Run 'npm run update-geoip' first"
    catch error
      @logger.error "Error loading IP2Location database:", error

    # Setup Redis with error handling
    redisConfig = @config.settings?.redis or {}
    @redis = new Redis
      host: redisConfig.host or 'localhost'
      port: redisConfig.port or 6379
      db: redisConfig.db or 0
      keyPrefix: 'proxy:'
      retryStrategy: (times) ->
        return Math.min(times * 100, 3000)  # Max 3 second retry delay

    @redis.on 'error', (err) =>
      @logger.error "Redis error:", err

    @redis.on 'ready', =>
      @logger.info "Redis connected"
      # Flush cache on startup
      @redis.flushall().then =>
        @logger.info "Redis cache flushed on startup"

    @regexCache = new Map()
    @activeResponses = new WeakMap()
    @rateLimiters = new Map()
    @requestQueues = new Map()
    @apps = new Map()

    rateLimitCapacity = @config.settings?.rate_limit?.capacity or 10
    rateLimitFillRate = @config.settings?.rate_limit?.fill_rate or 5

    for site in @config.sites
      @sites.set(site.port, site)
      @rateLimiters.set(site.port, new RateLimiter(rateLimitCapacity, rateLimitFillRate))
      @requestQueues.set(site.port, [])

      # Initialize Express app for each site
      app = express()
      app.use(customRoutes(site, @config))
      app.use(@handleRequest(site))
      @apps.set(site.port, app)

      @regexCache.set site.port,
        hostPattern: new RegExp("https?://#{site.original_host}", 'g')
        wpPattern: new RegExp("https?://[\\w\\d]+\\.wp\\.com/#{site.original_host}", 'g')
        trackingPatterns: site.tracking_scripts?.map (script) ->
          new RegExp("<script[^>]*src=[\"']#{script}[\"'][^>]*>.*?</script>", 'gs')
        domainPatterns: site.additional_domains?.map (domain) ->
          new RegExp("https?://#{domain}", 'g')

  getRealIP: (req) ->
    forwardedFor = req.headers['x-forwarded-for']
    if forwardedFor
      ips = forwardedFor.split(',').map((ip) -> ip.trim())
      for ip in ips
        continue if /^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)/.test(ip)
        return ip
    return req.connection.remoteAddress

  getGeoInfo: (ip) ->
    return null unless @ip2location?
    try
      result = @ip2location.getAll(ip)
      return {
        country: result.countryShort
        countryLong: result.countryLong
        isEU: result.countryShort in [
          'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR',
          'DE', 'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL',
          'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE'
        ]
      }
    catch error
      @logger.error "IP2Location lookup error for #{ip}:", error
      return null

  start: ->
    @apps.forEach (app, port) =>
      server = http.createServer(app)

      server.on 'error', (error) =>
        @logger.error "Server error on port #{port}:", error

      server.keepAliveTimeout = 60000
      server.headersTimeout = 65000

      server.listen port, 'localhost', =>
        @logger.info "Server started on localhost:#{port}"

  sendError: (res, status, message) ->
    return if @activeResponses.get(res)
    @activeResponses.set(res, true)

    try
      res.status(status).json
        error: message
        status: status
    catch error
      @logger.error "Error sending error response:", error

  shouldCloak: (req) ->
    realIP = @getRealIP(req)
    geoInfo = @getGeoInfo(realIP)

    clientInfo =
      ip: realIP
      geo: geoInfo
      userAgent: req.headers['user-agent']
      path: req.path
      query: req.query
      headers: req.headers
      timestamp: new Date()
      method: req.method
      protocol: req.protocol
      hostname: req.hostname

    try
      result = cloakFn(clientInfo)
      if result
        @logger.info 'Cloaked request',
          result: if typeof result is 'string' then "redirect:#{result}" else 'block'
          client: clientInfo
        return result
      return false
    catch error
      @logger.error "Cloak function error:", error
      return false

  processNextInQueue: (site) ->
    queue = @requestQueues.get(site.port)
    if queue.length > 0
      {req, res} = queue.shift()
      @processProxyRequest(req, res, site)

  handleRequest: (site) -> (req, res, next) =>
    requestTimeout = null

    try
      requestTimeout = setTimeout =>
        @sendError(res, 504, "Request timeout after #{@config.settings?.request_timeout or DEFAULT_REQUEST_TIMEOUT}ms")
        req.destroy()
      , @config.settings?.request_timeout or DEFAULT_REQUEST_TIMEOUT

      if cloakResult = @shouldCloak(req)
        clearTimeout(requestTimeout)
        if typeof cloakResult is 'string'
          return res.redirect(cloakResult)
        return @sendError(res, 403, "Access denied")

      rateLimiter = @rateLimiters.get(site.port)

      if rateLimiter.tryAcquire()
        @processProxyRequest(req, res, site)
      else
        queue = @requestQueues.get(site.port)
        if queue.length < 100
          queue.push({req, res})
          @logger.info "Request queued for #{site.port}. Queue size: #{queue.length}"
        else
          @sendError(res, 429, "Too Many Requests")

    catch error
      @logger.error "Request handler error:", error
      @sendError(res, 500, "Internal server error")
    finally
      clearTimeout(requestTimeout) if requestTimeout?

  processProxyRequest: (req, res, site) ->
    @logger.info "#{req.method} #{req.url} (#{site.port})"

    @activeResponses.set(res, false)

    try
      if req.url == '/'
        targetUrl = new URL("https://#{site.original_host}")
      else
        targetUrl = new URL(req.url, "https://#{site.original_host}")

      @logger.debug "Proxying to: #{targetUrl.toString()}"

      # Check if it's a custom route
      isCustomRoute = customRoutes(site, @config).stack.some((layer) -> layer.regexp.test(req.path))

      # Cache handling
      if req.method == 'GET' and !isCustomRoute
        cacheKey = "site:#{site.port}:#{req.method}:#{req.url}"

        # Check cloaking before using cache
        cloakResult = @shouldCloak(req)
        if !cloakResult
          try
            cached = await @redis.get(cacheKey)
            if cached
              @logger.debug "Cache hit for #{cacheKey}"
              return if @activeResponses.get(res)
              @activeResponses.set(res, true)
              cached = JSON.parse(cached)
              res.writeHead(cached.status, cached.headers)
              res.end(cached.body)
              @processNextInQueue(site)
              return
          catch error
            @logger.error "Cache error:", error
        else
          # Handle cloaking result
          if typeof cloakResult is 'string'
            return res.redirect(cloakResult)
          else
            return @sendError(res, 403, "Access denied")

      headers = { ...req.headers }
      headers.host = site.original_host
      headers['accept-encoding'] = 'gzip'

      options =
        hostname: site.original_host
        path: targetUrl.pathname + targetUrl.search
        method: req.method
        headers: headers
        timeout: @config.settings?.request_timeout or DEFAULT_REQUEST_TIMEOUT

      proxyReq = https.request options, (proxyRes) =>
        return if @activeResponses.get(res)

        @logger.debug "Response status: #{proxyRes.statusCode}"

        responseHeaders = {}
        Object.entries(proxyRes.headers).forEach ([key, value]) ->
          if !['content-length', 'content-encoding', 'transfer-encoding'].includes(key.toLowerCase())
            responseHeaders[key] = value

        chunks = []
        proxyRes.on 'data', (chunk) -> chunks.push(chunk)

        proxyRes.on 'end', =>
          try
            return if @activeResponses.get(res)

            body = Buffer.concat(chunks)

            if proxyRes.headers['content-encoding'] == 'gzip'
              body = zlib.gunzipSync(body)

            contentType = proxyRes.headers['content-type'] or ''
            isText = contentType.includes('text') or
                    contentType.includes('javascript') or
                    contentType.includes('json') or
                    contentType.includes('xml')

            if isText
              content = body.toString('utf8')
              @logger.debug "Processing content..."
              content = @processContent(content, site)

              if req.method == 'GET' and proxyRes.statusCode == 200 and !isCustomRoute
                try
                  await @redis.set cacheKey, JSON.stringify(
                    status: proxyRes.statusCode
                    headers: responseHeaders
                    body: content
                  ), 'EX', CACHE_TTL
                catch error
                  @logger.error "Cache save error:", error

              @activeResponses.set(res, true)
              res.writeHead(proxyRes.statusCode, proxyRes.statusMessage, responseHeaders)
              res.end(content)
            else
              @activeResponses.set(res, true)
              res.writeHead(proxyRes.statusCode, proxyRes.statusMessage, responseHeaders)
              res.end(body)

          catch error
            @logger.error "Process error:", error
            @sendError(res, 500, "Processing error") unless @activeResponses.get(res)
          finally
            @processNextInQueue(site)

      proxyReq.on 'error', (error) =>
        @logger.error "Proxy error:", error
        @sendError(res, 502, "Upstream error") unless @activeResponses.get(res)
        @processNextInQueue(site)

      proxyReq.on 'timeout', =>
        proxyReq.destroy()
        @sendError(res, 504, "Gateway timeout") unless @activeResponses.get(res)
        @processNextInQueue(site)

      if ['POST', 'PUT', 'PATCH'].includes(req.method)
        req.pipe(proxyReq)
      else
        proxyReq.end()

    catch error
      @logger.error "Request processing error:", error
      @sendError(res, 500, "Internal server error") unless @activeResponses.get(res)
      @processNextInQueue(site)

  processContent: (content, site) ->
    try
      patterns = @regexCache.get(site.port)
      portStr = if site.port not in [80, 443] then ":#{site.port}" else ''
      newHost = "//#{site.new_host}#{portStr}"

      # String replacements first using split/join for multiple replacements
      if site.string_replacements?
        for replacement in site.string_replacements
          @logger.debug "Replacing all instances of '#{replacement.from}' with '#{replacement.to}'"
          content = content.split(replacement.from).join(replacement.to)

      # Domain replacements
      content = content
        .replace(patterns.hostPattern, newHost)
        .replace(patterns.wpPattern, newHost)

      if patterns.domainPatterns?
        for pattern, i in patterns.domainPatterns
          domain = site.additional_domains[i]
          content = content.replace(pattern, "//#{domain}")

      if patterns.trackingPatterns?
        for pattern in patterns.trackingPatterns
          content = content.replace(pattern, '')

      if site.inject_script?
        content = content.replace('</body>', "#{site.inject_script}</body>")

      content
    catch error
      @logger.error "Content processing error:", error
      throw error

# Main execution
try
  configPaths = [
    '/etc/rust-proxy/config.yml'
    'config.yml'
  ]

  configPath = configPaths.find (path) -> fs.existsSync(path)

  unless configPath?
    throw new Error('No config file found')

  console.log "Loading configuration from #{configPath}"
  configFile = fs.readFileSync(configPath, 'utf8')
  config = yaml.load(configFile)

  # Setup logger
  logger = setupLogger(config)

  # Create and start proxy service
  proxy = new ProxyService(config, logger)
  proxy.start()

  # Handle process errors
  process.on 'uncaughtException', (error) ->
    logger.error 'Uncaught Exception:', error
    # Keep running despite errors

  process.on 'unhandledRejection', (reason, promise) ->
    logger.error 'Unhandled Rejection:', { promise, reason }
    # Keep running despite errors

catch error
  console.error('Startup Error:', error.message)
  process.exit(1)# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
