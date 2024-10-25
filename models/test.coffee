# vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2
Preact = require 'preact'
renderToString = require 'preact-render-to-string'
babel = require '@babel/core'

# Dynamic render function for handling both JSX and placeholders inside templates
renderTemplate = (templateString, data) ->

  # Regular expression to match {expression} within the template string
  expressionRegex = /{([^}]+)}/g

  # Replacing expressions found in the template string by evaluating them
  processedTemplate = templateString.replace(expressionRegex, (match, expression) ->

    try
      # Create a scoped function that destructures props (data) from `data`
      scopedFunction = """
        const {#{Object.keys(data).join(', ')}} = props;
        (#{expression.trim()});
      """

      # Use Babel to transpile JSX code inside the expression into valid JavaScript, using Preact instead of React
      transpiledExpression = babel.transform(scopedFunction, {
        plugins: ['@babel/plugin-transform-react-jsx'],
        presets: [
          ['@babel/preset-react', { pragma: 'Preact.createElement', pragmaFrag: 'Preact.Fragment' }]
        ]
      }).code

      # Use `new Function` to evaluate the transpiled JSX expression within the `data` (props) context
      result = (new Function('Preact', 'props', transpiledExpression))(Preact, data)

      # If the result is JSX (output object), render it as a string
      if typeof result == 'object'
        renderToString(result)  # Convert JSX to HTML string
      else
        result  # Return the raw result for non-JSX expressions (strings, numbers)

    catch error
      console.error "Error evaluating expression: #{expression} ->", error.message
      match  # Return the original {expression} if evaluation error occurs
  )

  # Returning the final processed template after replacing all the expressions
  return processedTemplate


# Test 1: Simple string interpolation without JSX
simpleTemplate = "hey my name is {fuck}, and I am {age} years old."

# Data for placeholders in the template
simpleData =
  fuck: "john"
  age: 25

# Output the rendered template after replacing placeholders with data
console.log renderTemplate(simpleTemplate, simpleData)

# Test 2: Handling JSX and logic-based expressions
templateWithLogic = """
  Hello, {firstName || 'Friend'},
  <p>{ isRegisteredDemocrat ? "You're a Democrat." : "You're not a Democrat." }</p>
  Thanks for visiting us!
  <html>
    <p>{"Just a string"}</p>
    { isRegisteredDemocrat && (
      <p>You are a democrat.</p>
    )}
  </html>
"""

# Data to be injected into the template
dataWithLogic =
  firstName: null
  isRegisteredDemocrat: true

# Output the template after dynamic rendering of expressions and JSX elements
console.log renderTemplate(templateWithLogic, dataWithLogic)
