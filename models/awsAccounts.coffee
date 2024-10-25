# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
{ log } = console
{ env } = process

{ mongoose, redis } = require './../lib/database'

Schema = mongoose.Schema
{ basePlugin, EXPOSE } = require './../lib/models'

modelOpts = {
  name: 'AWSAccount'
  schema: {
    collection: 'awsaccounts'
    strict: false
  }
}

AWSAccount = new Schema {

  name: {
    type: String
    required: true
    trim: true
  }

  AWS_ACCESS_KEY_ID: {
    type: String
    required: true
    trim: true
  }

  AWS_SECRET_ACCESS_KEY: {
    type: String
    required: true
    trim: true
  }

  AWS_REGION: {
    type: String
    required: true
    enum: [
      'us-east-1'
      'us-east-2'
      'us-west-1'
      'us-west-2'
      'ca-central-1'
      'ca-west-1'
      'eu-north-1'
      'eu-west-3'
      'eu-west-2'
      'eu-west-1'
      'eu-central-1'
      'eu-south-1'
      'eu-south-2'
      'eu-central-2'
      'ap-south-1'
      'ap-northeast-1'
      'ap-northeast-2'
      'ap-northeast-3'
      'ap-southeast-1'
      'ap-southeast-2'
      'ap-southeast-3'
      'ap-east-1'
      'sa-east-1'
      'cn-north-1'
      'cn-northwest-1'
      'us-gov-east-1'
      'us-gov-west-1'
      'us-isob-east-1'
      'us-iso-east-1'
      'us-iso-west-1'
      'me-south-1'
      'af-south-1'
      'me-central-1'
      'ap-south-2'
      'ap-southeast-4'
      'il-central-1'
      'ap-southeast-5'
    ]
    default: 'us-east-1'
  }

}, modelOpts.schema

AWSAccount.plugin(basePlugin)

# POST /awsaccounts/:_id/test
AWSAccount.methods.test = (opt = {}) ->
  throw new Error 'AWSAccount.test not implemented'

model = mongoose.model modelOpts.name, Event
module.exports = EXPOSE(model)

