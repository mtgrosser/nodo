require 'rake'
require 'rake/testtask'
require 'rdoc/task'

desc 'Default: run unit tests.'
task :default => :test

desc 'Run all tests'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
  t.warning = false 
end
