ENV['NODE_ENV'] = ENV['RAILS_ENV'] = 'test'

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'debug'

require 'minitest/reporters'
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

require 'minitest/autorun'

require 'nodo'

# Enable to print debug messages
# Nodo.debug = true
