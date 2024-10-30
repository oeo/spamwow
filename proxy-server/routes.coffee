# routes.coffee
# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
express = require('express')

module.exports = (site, config) ->
  router = express.Router()

  # Example unsubscribe route
  router.get '/unsubscribe', (req, res) ->
    email = req.params.email
    siteHost = site.original_host

    res.json
      status: 'success'
      message: "Unsubscribed from #{siteHost}"

  # Example click tracking
  router.get '/click/:code', (req, res) ->
    code = req.params.code
    siteHost = site.original_host
    # Track click and redirect
    res.json { status: 'success', site }

  return router

