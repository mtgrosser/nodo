ENV['NODE_ENV'] = ENV['RAILS_ENV'] = 'test'

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'byebug'
require 'minitest/autorun'

require 'nodo'
