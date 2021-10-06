[![Gem Version](https://badge.fury.io/rb/nodo.svg)](http://badge.fury.io/rb/nodo)  [![build](https://github.com/mtgrosser/nodo/actions/workflows/build.yml/badge.svg)](https://github.com/mtgrosser/nodo/actions/workflows/build.yml)

# Nōdo – call Node.js from Ruby

`Nodo` provides a Ruby environment to interact with JavaScript running inside a Node process.

ノード means "node" in Japanese.

## Why Nodo?

Nodo will dispatch all JS function calls to a single long-running Node process.

JavaScript code is run in a namespaced environment, where you can access your initialized
JS objects during sequential function calls without having to re-initialize them.

IPC is done via unix sockets, greatly improving performance over classic process/eval solutions.

## Installation

In your Gemfile:

```ruby
gem 'nodo'
```

### Node.js

Nodo requires a working installation of Node.js.

If the executable is located in your `PATH`, no configuration is required. Otherwise, the path to to binary can be set using:

```ruby
Nodo.binary = '/usr/local/bin/node'
```

## Usage

In Nodo, you define JS functions as you would define Ruby methods:

```ruby
class Foo < Nodo::Core
  
  function :say_hi, <<~JS
    (name) => {
      return `Hello ${name}!`;
    }
  JS
  
end

foo = Foo.new
foo.say_hi('Nodo')
=> "Hello Nodo!"
```

### Using npm modules

Install your modules to `node_modules`:

```shell
$ yarn add uuid
```

`require`ing your dependencies will make the library available as a `const` with the same name:

```ruby
class Bar < Nodo::Core
  require :uuid

  function :v4, <<~JS
    () => {
      return uuid.v4();
    }
  JS
end

bar = Bar.new
bar.v4 => "b305f5c4-db9a-4504-b0c3-4e097a5ec8b9"
```


### Aliasing requires

If the library name cannot be used as name of the constant, the `const` name
can be given using hash syntax:

```ruby
class FooBar < Nodo::Core
  require commonjs: '@rollup/plugin-commonjs'
end
```

### Setting NODE_PATH

By default, `./node_modules` is used as the `NODE_PATH`.

To set a custom path:
```ruby
Nodo.modules_root = 'path/to/node_modules'
```

For Rails applications, it will be set to `vendor/node_modules`. 
To use the Rails 6 default of putting `node_modules` to `RAILS_ROOT`:

```ruby
# config/initializers/nodo.rb
Nodo.modules_root = Rails.root.join('node_modules')
```

### Defining JS constants

```ruby
class BarFoo < Nodo::Core
  const :HELLO, "World"
end
```

### Execute some custom JS during initialization

```ruby
class BarFoo < Nodo::Core

  script <<~JS
    // custom JS to be executed during initialization
    // things defined here can later be used inside functions
    const bigThing = someLib.init();
  JS
end
```

### Inheritance

Subclasses will inherit functions, constants, dependencies and scripts from their superclasses, while only functions can be overwritten.

```ruby
class Foo < Nodo::Core
  function :foo, "() => 'superclass'"
end

class SubFoo < Foo
  function :bar, "() => { return 'calling' + foo() }"
end

class SubSubFoo < SubFoo
  function :foo, "() => 'subsubclass'"
end

Foo.new.foo => "superclass"
SubFoo.new.bar => "callingsuperclass"
SubSubFoo.new.bar => "callingsubsubclass"
```

### Async functions

`Nodo` supports calling `async` functions from Ruby. 
The Ruby call will happen synchronously, i.e. it will block until the JS function resolves:

```ruby
class SyncFoo < Nodo::Core
  function :do_something, <<~JS
    async () => { return await asyncFunc(); }
  JS
end
```
