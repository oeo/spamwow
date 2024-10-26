# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log, L } = require './../lib/logger'
{ exit, env } = process

require './../lib/env'

{ mongoose, redis, connected } = require './../lib/database'

helpers = require './../lib/helpers'

_ = require 'lodash'

{
  AwsAccount
} = require './../models'

run = ->
  await connected()
  start = new Date

  newCred = new AwsAccount({
    name: 'NMAP AWS Credential'
    AWS_ACCESS_KEY_ID: env.TMP_AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY: env.TMP_AWS_SECRET_ACCESS_KEY
    AWS_REGION: env.TMP_AWS_REGION
  })

  result = await newCred.save()

  return { elapsed: new Date() - start }

module.exports = {
  run
}

if !module.parent
  await run()
  exit 0

