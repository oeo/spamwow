# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
require '../lib/env'

{ env, exit } = require 'process'
{ L, log } = require '../lib/logger'

https = require 'https'
http = require 'http'
zlib = require 'zlib'
{ parse } = require 'url'
{ createServer } = require 'http'

{ redis, mongoose, ready } = require '../lib/database'
{ ProxyWebsites } = require '../models'

proxyWebsite = null

REQUEST_TIMEOUT = 5000

# track active requests to prevent duplicate processing
activeResponses = new Map()

# create the http server to handle all requests
server = createServer (req, res) ->
  if !proxyWebsite
    res.writeHead 503, 'Content-Type': 'text/plain'
    res.end 'Proxy website not initialized'
    return

  # add detection of actual host from headers
  actualHost = req.headers['x-forwarded-host'] || req.headers.host || ''
  protocol = if (req.headers['x-forwarded-proto'] || '').includes('https') || req.connection.encrypted then 'https' else 'http'

  { pathname } = parse req.url, true

  # parse the target host and determine protocol (http or https)
  originalUrl = proxyWebsite.originalHost
  cleanHost = originalUrl.replace(/^https?:\/\//, '').replace(/\/+$/, '')  # remove protocol and trailing slashes

  # build the request options
  options =
    hostname: cleanHost
    path: req.url
    method: req.method
    headers: { ...req.headers }  # clone the headers

  # remove or modify headers that could cause redirects to the original site
  delete options.headers['host']  # remove the host header
  delete options.headers['origin']
  delete options.headers['referer']
  
  # set the correct host header for the target
  options.headers['host'] = cleanHost

  # use https or http based on the original target's protocol
  targetProtocol = if proxyWebsite.originalHost.startsWith('https://') then 'https' else 'http'
  requestModule = if targetProtocol == 'https' then https else http

  # proxy to target host
  proxyReq = requestModule.request options, (proxyRes) =>
    return if activeResponses.get(res)

    responseHeaders = {}
    for [key, value] in Object.entries(proxyRes.headers)
      # skip transfer-encoding and content-encoding, we'll handle them manually
      if !['content-length', 'content-encoding', 'transfer-encoding'].includes(key.toLowerCase())
        responseHeaders[key] = value

    # add cors headers
    responseHeaders['Access-Control-Allow-Origin'] = '*'
    responseHeaders['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS'
    responseHeaders['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'

    # collect response chunks
    chunks = []
    proxyRes.on 'data', (chunk) -> chunks.push(chunk)

    proxyRes.on 'end', ->
      try
        return if activeResponses.get(res)

        body = Buffer.concat(chunks)
        contentType = proxyRes.headers['content-type'] || ''
        
        # check content encoding before attempting any modifications
        encoding = proxyRes.headers['content-encoding']?.toLowerCase()
        
        try
          if encoding == 'gzip'
            body = zlib.gunzipSync(body)
          else if encoding == 'deflate'
            body = zlib.inflateSync(body)
          else if encoding == 'br'  # handle brotli compression
            body = zlib.brotliDecompressSync(body)
        catch error
          console.error "Decompression error:", error
          # if decompression fails, send original content
          activeResponses.set(res, true)
          res.writeHead(proxyRes.statusCode, proxyRes.headers)
          res.end(body)
          return

        isTextContent = contentType.includes('text') || 
                       contentType.includes('json') || 
                       contentType.includes('xml') || 
                       contentType.includes('javascript') ||
                       contentType.includes('application/x-javascript')

        if isTextContent
          content = body.toString('utf8')

          # replace the original host with the new host in all urls
          originalUrlPattern = proxyWebsite.originalHost.replace(/^https?:\/\//, '')
          newBaseUrl = "#{protocol}://#{actualHost}"
          
          # create regex patterns for different url formats
          patterns = [

            # absolute urls with protocol
            [new RegExp("https?://#{originalUrlPattern}/", 'g'), "#{newBaseUrl}/"]
            [new RegExp("https?://#{originalUrlPattern}([^/])", 'g'), "#{newBaseUrl}/$1"]

            # protocol-relative urls
            [new RegExp("//#{originalUrlPattern}/", 'g'), "//#{actualHost}/"]
            [new RegExp("//#{originalUrlPattern}([^/])", 'g'), "//#{actualHost}/$1"]

            # absolute paths starting with single quote
            [new RegExp("'/((?!//)[^']*)'", 'g'), "'#{newBaseUrl}/$1'"]

            # absolute paths starting with double quote
            [new RegExp('"/((?!//)[^"]*)"', 'g'), "\"#{newBaseUrl}/$1\""]
          ]
          
          # apply all url replacements
          for [pattern, replacement] in patterns
            content = content.replace(pattern, replacement)

          # apply any additional string replacements from config
          for replacement in (proxyWebsite.stringReplacements || [])
            content = content.replace(new RegExp(replacement.find, 'g'), replacement.replace)

          # handle header/footer injections for html
          if contentType.includes('text/html')
            headerScripts = proxyWebsite.injectScriptHeader || ''
            footerScripts = proxyWebsite.injectScriptFooter || ''

            # inject into <head>
            if headerScripts and content.includes('<head>')
              content = content.replace('<head>', "<head>#{headerScripts}")

            # inject scripts before </body>
            if footerScripts
              if content.includes('</body>')
                content = content.replace('</body>', "#{footerScripts}</body>")
              else if content.includes('</html>')
                content = content.replace('</html>', "#{footerScripts}</html>")

          # send modified text response
          activeResponses.set(res, true)
          res.writeHead(proxyRes.statusCode, responseHeaders)
          res.end(content)

        else
          # for binary content, preserve original headers including content-encoding
          activeResponses.set(res, true)
          res.writeHead(proxyRes.statusCode, proxyRes.headers)
          res.end(body)

      catch error
        console.error "Error processing response: #{error.message}"
        if !activeResponses.get(res)
          res.writeHead(500, 'Content-Type': 'text/plain')
          res.end("Error processing response")

  # handle errors in the proxy request
  proxyReq.on 'error', (error) =>
    console.error "Proxy error:", error.message
    if !activeResponses.get(res)
      res.writeHead(502, 'Content-Type': 'text/plain')
      res.end('Proxy error')

  # set request timeout
  proxyReq.setTimeout REQUEST_TIMEOUT, ->
    proxyReq.destroy()
    if !activeResponses.get(res)
      res.writeHead(504, 'Content-Type': 'text/plain')
      res.end('Gateway timeout')

  # pipe body for post, put, etc.
  if ['POST', 'PUT', 'PATCH'].includes(req.method)
    req.pipe(proxyReq)
  else
    proxyReq.end()

# websocket upgrade handler
server.on 'upgrade', (req, socket, head) ->
  if !proxyWebsite
    socket.destroy()
    return

  wsProtocol = if proxyWebsite.originalHost.startsWith('http://') then 'ws' else 'wss'
  wsUrl = "#{wsProtocol}://#{proxyWebsite.originalHost}"

  wsOptions =
    hostname: proxyWebsite.originalHost
    path: req.url
    headers:
      host: proxyWebsite.originalHost
      'x-forwarded-for': req.connection.remoteAddress

  ws = https.request wsOptions
  ws.end()
  
  socket.pipe(ws).pipe(socket)

# start the proxy server
run = (->
  await ready()

  proxyWebsite = await ProxyWebsites.findOne(_id: process.env.PROXY_WEBSITE_ID)

  if !proxyWebsite
    throw new Error "Proxy website not found"

  server.listen proxyWebsite.port
)

if !module.parent
  run()
