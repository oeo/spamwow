# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
###
Cloaking Function API Documentation

This function receives a client object with the following properties:
  client = {
    ip: string               # Real IP address (handles X-Forwarded-For)
    geo: {                   # GeoIP information (null if lookup fails)
      country: string        # Two-letter country code (e.g., 'US')
      countryLong: string    # Full country name (e.g., 'United States')
      isEU: boolean         # Whether country is in EU
    }
    userAgent: string        # User-Agent header
    path: string            # Request path
    query: object           # Parsed query parameters
    headers: object         # All request headers
    timestamp: Date         # Request timestamp
    method: string          # HTTP method
    protocol: string        # Protocol used (http/https)
    hostname: string        # Requested hostname
  }

Return values:
  false                    # Allow the request
  true                     # Block with 403
  "https://example.com"    # Redirect to URL

Example implementation:
###

module.exports = (client) ->
  # console.log("Cloaking function called", { client })

  # Block specific countries
  if client.geo?.country? and client.geo.country.length is 2
    if client.geo.country !in ['US', 'CA', 'GB']
      console.log("Blocking country: #{client.geo.country}")
      return "https://google.com"

  # Block EU traffic (GDPR)
  if client.geo?.isEU
    console.log("Blocking EU traffic")
    return "https://gdpr-notice.example.com"

  # Block known bot patterns
  botPatterns = [
    /bot/i,
    /crawler/i,
    /spider/i,
    /googlebot/i
  ]
  if client.userAgent and botPatterns.some((pattern) -> pattern.test(client.userAgent))
    console.log("Blocking bot: #{client.userAgent}")
    return "https://google.com"

  # Block specific IPs
  blockedIps = ['1.2.3.4', '5.6.7.8']
  if blockedIps.includes(client.ip)
    console.log("Blocking IP: #{client.ip}")
    return true

  # Block based on request method
  if client.method not in ['GET', 'HEAD', 'POST']
    console.log("Blocking request with method: #{client.method}")
    return true

  # Block based on query parameters
  if client.query?.debug
    console.log("Blocking request with debug query parameter")
    return true

  # Block based on missing headers
  if !client.headers['accept-language']
    console.log("Blocking request without Accept-Language header")
    return true

  # Allow everything else
  return false

