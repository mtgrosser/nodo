[![Gem Version](https://badge.fury.io/rb/jass-core.svg)](http://badge.fury.io/rb/jass-core)

# Jass::Core – call Node.js from Ruby

Jass::Core provides a Ruby environment to call JavaScript running inside a Node process.

## Installation

In your Gemfile:

```ruby
gem 'jass-core'
```

### Node.js

Jass requires a working installation of Node.js.

## Usage

```ruby
class Foo < Jass::Core
  
  function :say_hi, <<~JS
    (name) => {
      return `Hello ${name}!`;
    }
  JS
  
end

foo = Foo.new
foo.say_hi('Jass')
=> "Hello Jass!"
```

### Using npm modules

Install your modules to `node_modules`:

```shell
yarn add uuid
```

```ruby
class Bar < Jass::Core
  require :uuid

  function :v4, <<~JS
    () => {
      return uuid.v4();
    }
  JS
end

bar = Bar.new
bar.v4 => '"b305f5c4-db9a-4504-b0c3-4e097a5ec8b9"
```

### Aliasing requires

```ruby
class FooBar < Jass::Core
  require commonjs: '@rollup/plugin-commonjs'
end
```

### Setting NODE_PATH

By default, `./node_modules` is used as the `NODE_PATH`.

To set a custom path:
```ruby
Jass.modules_root = 'path/to/node_modules'

# For Rails
# config/initializers/jass.rb
Jass.modules_root = Rails.root.join('vendor', 'node_modules')
```
The modules root can also be given during instantiation of the class:

```ruby
foo = Foo.new('path/to/node_modules')
```

### Defining JS constants

```ruby
class BarFoo < Jass::Core
  const :HELLO, "World"
end
```

### Execute some custom JS during initialization

```ruby
class BarFoo < Jass::Core

  script <<~JS
    // some custom JS
    // to be executed during initialization
  JS
end
```
