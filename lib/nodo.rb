require 'pathname'
require 'json'
require 'fileutils'
require 'tmpdir'

module Nodo
  class << self
    attr_accessor :modules_root, :env, :binary
  end
  self.modules_root = './node_modules'
  self.env = {}
  self.binary = 'node'
end

require_relative 'nodo/version'
require_relative 'nodo/errors'
require_relative 'nodo/dependency'
require_relative 'nodo/function'
require_relative 'nodo/script'
require_relative 'nodo/constant'
require_relative 'nodo/client'
require_relative 'nodo/core'

require_relative 'nodo/railtie' if defined?(Rails)
