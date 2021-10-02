lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'jass/core/version'

Gem::Specification.new do |s|
  s.name          = 'jass-core'
  s.version       = Jass::Core::VERSION
  s.date          = '2021-10-02'
  s.authors       = ['Matthias Grosser']
  s.email         = ['mtgrosser@gmx.net']
  s.license       = 'MIT'

  s.summary       = 'Call Node.js from Ruby'
  s.description   = 'Fast Ruby bridge to run JavaScript inside a Node process'
  s.homepage      = 'https://github.com/mtgrosser/jass-core'

  s.files = ['LICENSE', 'README.md'] + Dir['lib/**/*.rb']
  
  s.required_ruby_version = '>= 2.3.0'

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'byebug'
  s.add_development_dependency 'minitest'
end
