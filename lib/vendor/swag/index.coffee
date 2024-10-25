###
  Swag v0.6.1 <http://elving.github.com/swag/>
  Copyright 2012 Elving Rodriguez <http://elving.me/>
  Available under MIT license <https://raw.github.com/elving/swag/master/LICENSE>
###

module.exports = Swag = {}

Swag.helpers = {}

Swag.addHelper = (name, helper, argTypes = []) ->
  unless argTypes instanceof Array
    argTypes = [argTypes]
  Swag.helpers[name] = ->
    # Verify all required arguments have been supplied
    Utils.verify name, arguments, argTypes

    # Call all arguments which are functions to get their result
    args = Array.prototype.slice.apply(arguments)
    resultArgs = []
    for arg in args
      unless Utils.isHandlebarsSpecific(arg)
        arg = Utils.result(arg)
      resultArgs.push(arg)
    helper.apply @, resultArgs

Swag.registerHelpers = (localHandlebars) ->
  if localHandlebars
    Swag.Handlebars = localHandlebars
  else
    Swag.Handlebars = require 'handlebars'

  Swag.registerHelper = (name, helper) ->
    Swag.Handlebars.registerHelper name, helper

  for name, helper of Swag.helpers
    Swag.registerHelper name, helper

Swag.addHelper 'first', (array, count) ->
  count = parseFloat count unless Utils.isUndefined count
  if Utils.isUndefined(count) then array[0] else array.slice 0, count
, 'array'

Swag.addHelper 'withFirst', (array, count, options) ->
  count = parseFloat count unless Utils.isUndefined count
  if Utils.isUndefined count
    options = count
    options.fn array[0]
  else
    array = array.slice 0, count
    result = ''
    for item of array then result += options.fn array[item]
    result
, 'array'

Swag.addHelper 'last', (array, count) ->
  count = parseFloat count unless Utils.isUndefined count
  if Utils.isUndefined(count) then array[array.length - 1] else array.slice -count
, 'array'

Swag.addHelper 'withLast', (array, count, options) ->
  count = parseFloat count unless Utils.isUndefined count
  if Utils.isUndefined count
    options = count
    options.fn array[array.length - 1]
  else
    array = array.slice -count
    result = ''
    for item of array then result += options.fn array[item]
    result
, 'array'

Swag.addHelper 'after', (array, count) ->
  count = parseFloat count unless Utils.isUndefined count
  array.slice count
, ['array', 'number']

Swag.addHelper 'withAfter', (array, count, options) ->
  count = parseFloat count unless Utils.isUndefined count
  array = array.slice count
  result = ''
  for item of array then result += options.fn array[item]
  result
, ['array', 'number']

Swag.addHelper 'before', (array, count) ->
  count = parseFloat count unless Utils.isUndefined count
  array.slice 0, -count
, ['array', 'number']

Swag.addHelper 'withBefore', (array, count, options) ->
  count = parseFloat count unless Utils.isUndefined count
  array = array.slice 0, -count
  result = ''
  for item of array then result += options.fn array[item]
  result
, ['array', 'number']

Swag.addHelper 'join', (array, separator) ->
  array.join if Utils.isUndefined(separator) then ' ' else separator
, 'array'

Swag.addHelper 'sort', (array, field) ->
  if Utils.isUndefined field
    array.sort()
  else
    array.sort (a, b) -> a[field] > b[field]
, 'array'

Swag.addHelper 'withSort', (array, field, options) ->
  result = ''

  if Utils.isUndefined field
    options = field
    array = array.sort()
    result += options.fn(item) for item in array
  else
    array = array.sort (a, b) -> a[field] > b[field]
    result += options.fn(array[item]) for item of array

  result
, 'array'

Swag.addHelper 'length', (array) ->
  array.length
, 'array'

Swag.addHelper 'lengthEqual', (array, length, options) ->
  length = parseFloat length unless Utils.isUndefined length
  if array.length is length then options.fn this else options.inverse this
, ['array', 'number']

Swag.addHelper 'empty', (array, options) ->
  if not array or array.length <= 0 then options.fn this else options.inverse this
, 'safe:array'

Swag.addHelper 'any', (array, options) ->
  if array and array.length > 0 then options.fn this else options.inverse this
, 'safe:array'

Swag.addHelper 'inArray', (array, value, options) ->
  if value in array then options.fn this else options.inverse this
, ['array', 'string|number']

Swag.addHelper 'eachIndex', (array, options) ->
  result = ''

  for value, index in array
    result += options.fn item: value, index: index

  result
, 'array'

Swag.addHelper 'eachProperty', (obj, options) ->
  result = ''

  for key, value of obj
    result += options.fn key: key, value: value

  result
, 'object'
Swag.addHelper 'is', (value, test, options) ->
  if value and value is test then options.fn this else options.inverse this
, ['safe:string|number', 'safe:string|number']

Swag.addHelper 'isnt', (value, test, options) ->
  if not value or value isnt test then options.fn this else options.inverse this
, ['safe:string|number', 'safe:string|number']

Swag.addHelper 'gt', (value, test, options) ->
  if value > test then options.fn this else options.inverse this
, ['safe:string|number', 'safe:string|number']

Swag.addHelper 'gte', (value, test, options) ->
  if value >= test then options.fn this else options.inverse this
, ['safe:string|number', 'safe:string|number']

Swag.addHelper 'lt', (value, test, options) ->
  if value < test then options.fn this else options.inverse this
, ['safe:string|number', 'safe:string|number']

Swag.addHelper 'lte', (value, test, options) ->
  if value <= test then options.fn this else options.inverse this
, ['safe:string|number', 'safe:string|number']

Swag.addHelper 'or', (testA, testB, options) ->
  if testA or testB then options.fn this else options.inverse this
, ['safe:string|number', 'safe:string|number']

Swag.addHelper 'and', (testA, testB, options) ->
  if testA and testB then options.fn this else options.inverse this
, ['safe:string|number', 'safe:string|number']
Swag.Config =
  partialsPath: ''
  precompiledTemplates: yes
Dates = {}

Dates.padNumber = (num, count, padCharacter) ->
  padCharacter = '0'  if typeof padCharacter is 'undefined'
  lenDiff = count - String(num).length
  padding = ''
  padding += padCharacter while lenDiff-- if lenDiff > 0
  padding + num

Dates.dayOfYear = (date) ->
  oneJan = new Date(date.getFullYear(), 0, 1)
  Math.ceil (date - oneJan) / 86400000

Dates.weekOfYear = (date) ->
  oneJan = new Date(date.getFullYear(), 0, 1)
  Math.ceil (((date - oneJan) / 86400000) + oneJan.getDay() + 1) / 7

Dates.isoWeekOfYear = (date) ->
  target = new Date(date.valueOf())
  dayNr = (date.getDay() + 6) % 7
  target.setDate target.getDate() - dayNr + 3
  jan4 = new Date(target.getFullYear(), 0, 4)
  dayDiff = (target - jan4) / 86400000
  1 + Math.ceil(dayDiff / 7)

Dates.tweleveHour = (date) ->
  if date.getHours() > 12 then date.getHours() - 12 else date.getHours()

Dates.timeZoneOffset = (date) ->
  hoursDiff = (-date.getTimezoneOffset() / 60)
  result = Dates.padNumber Math.abs(hoursDiff), 4
  (if hoursDiff > 0 then '+' else '-') + result

Dates.format = (date, format) ->
  format.replace Dates.formats, (m, p) ->
    switch p
      when 'a' then Dates.abbreviatedWeekdays[date.getDay()]
      when 'A' then Dates.fullWeekdays[date.getDay()]
      when 'b' then Dates.abbreviatedMonths[date.getMonth()]
      when 'B' then Dates.fullMonths[date.getMonth()]
      when 'c' then date.toLocaleString()
      when 'C' then Math.round date.getFullYear() / 100
      when 'd' then Dates.padNumber date.getDate(), 2
      when 'D' then Dates.format date, '%m/%d/%y'
      when 'e' then Dates.padNumber date.getDate(), 2, ' '
      when 'F' then Dates.format date, '%Y-%m-%d'
      when 'h' then Dates.format date, '%b'
      when 'H' then Dates.padNumber date.getHours(), 2
      when 'I' then Dates.padNumber Dates.tweleveHour(date), 2
      when 'j' then Dates.padNumber Dates.dayOfYear(date), 3
      when 'k' then Dates.padNumber date.getHours(), 2, ' '
      when 'l' then Dates.padNumber Dates.tweleveHour(date), 2, ' '
      when 'L' then Dates.padNumber date.getMilliseconds(), 3
      when 'm' then Dates.padNumber date.getMonth() + 1, 2
      when 'M' then Dates.padNumber date.getMinutes(), 2
      when 'n' then '\n'
      when 'p' then (if date.getHours() > 11 then 'PM' else 'AM')
      when 'P' then Dates.format(date, '%p').toLowerCase()
      when 'r' then Dates.format date, '%I:%M:%S %p'
      when 'R' then Dates.format date, '%H:%M'
      when 's' then date.getTime() / 1000
      when 'S' then Dates.padNumber date.getSeconds(), 2
      when 't' then '\t'
      when 'T' then Dates.format date, '%H:%M:%S'
      when 'u' then (if date.getDay() is 0 then 7 else date.getDay())
      when 'U' then Dates.padNumber Dates.weekOfYear(date), 2
      when 'v' then Dates.format date, '%e-%b-%Y'
      when 'V' then Dates.padNumber Dates.isoWeekOfYear(date), 2
      when 'W' then Dates.padNumber Dates.weekOfYear(date), 2
      when 'w' then Dates.padNumber date.getDay(), 2
      when 'x' then date.toLocaleDateString()
      when 'X' then date.toLocaleTimeString()
      when 'y' then String(date.getFullYear()).substring 2
      when 'Y' then date.getFullYear()
      when 'z' then Dates.timeZoneOffset date
      else match

Dates.formats = /%(a|A|b|B|c|C|d|D|e|F|h|H|I|j|k|l|L|m|M|n|p|P|r|R|s|S|t|T|u|U|v|V|W|w|x|X|y|Y|z)/g
Dates.abbreviatedWeekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thur', 'Fri', 'Sat']
Dates.fullWeekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
Dates.abbreviatedMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
Dates.fullMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

# Port of formatDate-js library - https://github.com/michaelbaldry/formatDate-js
Swag.addHelper 'formatDate', (date, format) ->
  date = new Date date
  Dates.format date, format
, ['string|number|date', 'string']

Swag.addHelper 'now', (format) ->
  date = new Date()
  if Utils.isUndefined(format) then date else Dates.format(date, format)

# Modified version of - http://stackoverflow.com/a/3177838
Swag.addHelper 'timeago', (date) ->
  date = new Date date
  seconds = Math.floor((new Date() - date) / 1000)

  interval = Math.floor(seconds / 31536000)
  return "#{interval} years ago" if interval > 1

  interval = Math.floor(seconds / 2592000)
  return if interval > 1 then "#{interval} months ago"

  interval = Math.floor(seconds / 86400)
  return if interval > 1 then "#{interval} days ago"

  interval = Math.floor(seconds / 3600)
  return if interval > 1 then "#{interval} hours ago"

  interval = Math.floor(seconds / 60)
  return if interval > 1 then "#{interval} minutes ago"

  if Math.floor(seconds) is 0 then 'Just now' else Math.floor(seconds) + ' seconds ago'
, 'string|number|date'

HTML = {}

HTML.parseAttributes = (hash) ->
  Object.keys(hash).map((key) ->
    "#{key}=\"#{hash[key]}\""
  ).join ' '

Swag.addHelper 'ul', (context, options) ->
  "<ul #{HTML.parseAttributes(options.hash)}>" + context.map((item) ->
    "<li>#{options.fn(Utils.result item)}</li>"
  ).join('\n') + "</ul>"

Swag.addHelper 'ol', (context, options) ->
  "<ol #{HTML.parseAttributes(options.hash)}>" + context.map((item) ->
    "<li>#{options.fn(Utils.result item)}</li>"
  ).join('\n') + "</ol>"

Swag.addHelper 'br', (count, options) ->
  br = '<br>'

  unless Utils.isUndefined count
    i = 0

    while i < (parseFloat count) - 1
      br += '<br>'
      i++

  Utils.safeString br
Swag.addHelper 'inflect', (count, singular, plural, include) ->
  count = parseFloat count
  word = if count > 1 or count is 0 then plural else singular
  if Utils.isUndefined(include) or include is false then word else "#{count} #{word}"
, ['number', 'string', 'string']

Swag.addHelper 'ordinalize', (value) ->
  value = parseFloat value
  normal = Math.abs Math.round value

  if (normal % 100) in [11..13]
    "#{value}th"
  else
    switch normal % 10
      when 1 then "#{value}st"
      when 2 then "#{value}nd"
      when 3 then "#{value}rd"
      else "#{value}th"
, 'number'
Swag.addHelper 'log', (value) ->
  console.log value
, 'string|number|boolean|array|object'

Swag.addHelper 'debug', (value) ->
  console.log 'Context: ', this
  console.log 'Value: ', value unless Utils.isUndefined value
  console.log '-----------------------------------------------'
Swag.addHelper 'add', (value, addition) ->
  value = parseFloat value
  addition = parseFloat addition
  value + addition
, ['number', 'number']

Swag.addHelper 'subtract', (value, substraction) ->
  value = parseFloat value
  substraction = parseFloat substraction
  value - substraction
, ['number', 'number']

Swag.addHelper 'divide', (value, divisor) ->
  value = parseFloat value
  divisor = parseFloat divisor
  value / divisor
, ['number', 'number']

Swag.addHelper 'multiply', (value, multiplier) ->
  value = parseFloat value
  multiplier = parseFloat multiplier
  value * multiplier
, ['number', 'number']

Swag.addHelper 'floor', (value) ->
  value = parseFloat value
  Math.floor value
, 'number'

Swag.addHelper 'ceil', (value) ->
  value = parseFloat value
  Math.ceil value
, 'number'

Swag.addHelper 'round', (value) ->
  value = parseFloat value
  Math.round value
, 'number'
Swag.addHelper 'default', (value, defaultValue) ->
  value or defaultValue
, 'safe:string|number', 'string|number'

unless Ember?
  Swag.addHelper 'partial', (name, data, template) ->
    path = Swag.Config.partialsPath + name

    unless Swag.Handlebars.partials[name]?
      if !Utils.isUndefined template
        template = Swag.Handlebars.compile template if Utils.isString template
        Swag.Handlebars.registerPartial name, template
      else if define? and (Utils.isFunc define) and define.amd
        path = "!text#{path}" unless Swag.Config.precompiledTemplates
        require [path], (template) ->
          template = Swag.Handlebars.compile template if Utils.isString template
          Swag.Handlebars.registerPartial name, template
      else if require?
        template = require path
        template = Swag.Handlebars.compile template if Utils.isString template
        Swag.Handlebars.registerPartial name, template
      else
        Utils.err '{{partial}} no amd or commonjs module support found.'

    Utils.safeString Swag.Handlebars.partials[name] data
  , 'string'
Swag.addHelper 'toFixed', (number, digits) ->
  number = parseFloat number
  digits = if Utils.isUndefined digits then 0 else digits
  number.toFixed digits
, 'number'

Swag.addHelper 'toPrecision', (number, precision) ->
  number = parseFloat number
  precision = if Utils.isUndefined precision then 1 else precision
  number.toPrecision precision
, 'number'

Swag.addHelper 'toExponential', (number, fractions) ->
  number = parseFloat number
  fractions = if Utils.isUndefined fractions then 0 else fractions
  number.toExponential fractions
, 'number'

Swag.addHelper 'toInt', (number) ->
  parseInt number, 10
, 'number'

Swag.addHelper 'toFloat', (number) ->
  parseFloat number
, 'number'

Swag.addHelper 'digitGrouping', (number, separator) ->
  number = parseFloat number
  separator = if Utils.isUndefined separator then ',' else separator
  number.toString().replace /(\d)(?=(\d\d\d)+(?!\d))/g, "$1#{separator}"
, 'number'
Swag.addHelper 'lowercase', (str) ->
  str.toLowerCase()
, 'string'

Swag.addHelper 'uppercase', (str) ->
  str.toUpperCase()
, 'string'

Swag.addHelper 'capitalizeFirst', (str) ->
  str.charAt(0).toUpperCase() + str.slice(1)
, 'string'

Swag.addHelper 'capitalizeEach', (str) ->
  str.replace /\w\S*/g, (txt) -> txt.charAt(0).toUpperCase() + txt.substr(1)
, 'string'

Swag.addHelper 'titleize', (str) ->
  title = str.replace /[ \-_]+/g, ' '
  words = title.match(/\w+/g) || []
  capitalize = (word) -> word.charAt(0).toUpperCase() + word.slice(1)
  (capitalize word for word in words).join ' '
, 'string'

Swag.addHelper 'sentence', (str) ->
  str.replace /((?:\S[^\.\?\!]*)[\.\?\!]*)/g, (txt) -> txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase()
, 'string'

Swag.addHelper 'reverse', (str) ->
  str.split('').reverse().join ''
, 'string'

Swag.addHelper 'truncate', (str, length, omission) ->
  omission = '' if Utils.isUndefined omission
  if str.length > length then str.substring(0, length - omission.length) + omission else str
, ['string', 'number']

Swag.addHelper 'center', (str, spaces) ->
  spaces = Utils.result spaces
  space = ''
  i = 0

  while i < spaces
    space += '&nbsp;'
    i++

  "#{space}#{str}#{space}"
, 'string'

Swag.addHelper 'newLineToBr', (str) ->
  str.replace /\r?\n|\r/g, '<br>'
, 'string'

Swag.addHelper 'sanitize', (str, replaceWith) ->
  replaceWith = '-' if Utils.isUndefined replaceWith
  str.replace /[^a-z0-9]/gi, replaceWith
, 'string'

Utils = {}

Utils.isHandlebarsSpecific = (value) ->
  (value and value.fn?) or (value and value.hash?)

Utils.isUndefined = (value) ->
  (value is undefined or value is null) or
  Utils.isHandlebarsSpecific value

Utils.safeString = (str) ->
  new Swag.Handlebars.SafeString str

Utils.trim = (str) ->
  trim = if /\S/.test("\xA0") then /^[\s\xA0]+|[\s\xA0]+$/g else /^\s+|\s+$/g
  str.toString().replace trim, ''

Utils.isFunc = (value) ->
  typeof value is 'function'

Utils.isString = (value) ->
  typeof value is 'string'

Utils.result = (value) ->
  if Utils.isFunc value then value() else value

Utils.err = (msg) ->
  throw new Error msg

Utils.verify = (name, fnArg, argTypes = []) ->
  fnArg = Array.prototype.slice.apply(fnArg).slice(0, argTypes.length)
  for arg, i in fnArg
    msg = '{{'+name+'}} requires '+argTypes.length+' arguments '+argTypes.join(', ')+'.'
    if argTypes[i].indexOf('safe:') > -1
      Utils.err msg if Utils.isHandlebarsSpecific(arg)
    else
      Utils.err msg if Utils.isUndefined(arg)
