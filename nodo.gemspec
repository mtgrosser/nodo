lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'nodo/version'

Gem::Specification.new do |s|
  s.name          = 'nodo'
  s.version       = Nodo::VERSION
  s.date          = '2025-08-25'
  s.authors       = ['Matthias Grosser']
  s.email         = ['mtgrosser@gmx.net']
  s.license       = 'MIT'

  s.summary       = 'Call Node.js from Ruby'
  s.description   = 'Fast Ruby bridge to run JavaScript inside a Node process'
  s.homepage      = 'https://github.com/mtgrosser/nodo'

  s.files = ['LICENSE', 'README.md'] + Dir['lib/**/*.{rb,cjs}']
  
  s.required_ruby_version = '>= 3.0.0'
  
  s.add_dependency 'logger'
end
