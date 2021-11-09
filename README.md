[![Gem Version](https://badge.fury.io/rb/nodo.svg)](http://badge.fury.io/rb/nodo)
[![build](https://github.com/mtgrosser/nodo/actions/workflows/build.yml/badge.svg)](https://github.com/mtgrosser/nodo/actions/workflows/build.yml)

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

### Dynamic ESM imports

ES modules can be imported dynamically using `nodo.import()`:

```ruby
class DynamicFoo < Nodo::Core
  function :v4, <<~JS
    async () => {
      const uuid = await nodo.import('uuid');
      return await uuid.v4()
    }
  JS
end
```

Note that the availability of dynamic imports depends on your Node version.

### Alternate function definition syntax

JS code can also be supplied using the `code:` keyword argument:

```ruby
function :hello, code: "() => 'world'"
```

### Setting NODE_PATH

By default, `./node_modules` is used as the `NODE_PATH`.

To set a custom path:
```ruby
Nodo.modules_root = 'path/to/node_modules'
```

Also see: [Clean your Rails root](#Clean-your-Rails-root)

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

With the above syntax, the script code will be generated during class definition
time. In order to have the code generated when the first instance is created, the
code can be defined inside a block:

```ruby
class Foo < Nodo::Core
  script do
    <<~JS
      var definitionTime = #{Time.now.to_json};
    JS
  end
end
```

Note that the script will still be executed only once, when the first instance
of class is created.

### Inheritance

Subclasses will inherit functions, constants, dependencies and scripts from
their superclasses, while only functions can be overwritten.

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
The Ruby call will happen synchronously, i.e. it will block until the JS
function resolves:

```ruby
class SyncFoo < Nodo::Core
  function :do_something, <<~JS
    async () => { return await asyncFunc(); }
  JS
end
```

### Deferred function definition

By default, the function code string literal is created when the class
is defined. Therefore any string interpolation inside the code will take
place at definition time.

In order to defer the code generation until the first object instantiation,
the function code can be given inside a block:

```ruby
class Deferred < Nodo::Core
  function :now, <<~JS
    () => { return #{Time.now.to_json}; }
  JS

  function :later do
    <<~JS
      () => { return #{Time.now.to_json}; }
    JS
  end
end

instance = Deferred.new
sleep 5
instance.now => "2021-10-28 20:30:00 +0200"
instance.later => "2021-10-28 20:30:05 +0200"
```

The block will be invoked when the first instance is created. As with deferred
scripts, it will only be invoked once.

### Limiting function execution time

The default timeout for a single JS function call is 60 seconds and can be
set globally:

```ruby
Nodo.timeout = 5
```

If the execution of a single function call exceeds the timeout, `Nodo::TimeoutError`
is raised.

The timeout can also be set on a per-function basis:

```ruby
class Foo < Nodo::Core
  function :sleep, timeout: 1, code: <<~'JS'
    async (sec) => await new Promise(resolve => setTimeout(resolve, sec * 1000))
  JS
end

Foo.new.sleep(2)
=>  Nodo::TimeoutError raised
```

### Logging

By default, JS errors will be logged to `STDOUT`.

To set a custom logger:

```ruby
Nodo.logger = Logger.new('nodo.log')
```

In Rails applications, `Rails.logger` will automatically be set.


### Debugging

To get verbose debug output, set

```ruby
Nodo.debug = true
```

before instantiating any worker instances. The debug mode will be active during
the current process run.

To print a debug message from JS code:

```js
nodo.debug("Debug message");
```

### Evaluation

While `Nodo` is mainly function-based, it is possible to evaluate JS code in the
context of the defined object.

```ruby
foo = Foo.new.evaluate("3 + 5")
=> 8
```

Evaluated code can access functions, required dependencies and constants:

```ruby
class Foo < Nodo::Core
  const :BAR, 'bar'
  require :uuid
  function :hello, code: '() => "world"'
end

foo = Foo.new

foo.evaluate('BAR')
=> "bar"

foo.evaluate('uuid.v4()')
=> "f258bef3-0d6f-4566-ad39-d8dec973ef6b"

foo.evaluate('hello()')
=> "world"
```

Variables defined by evaluation are local to the current instance:

```ruby
one = Foo.new
one.evaluate('a = 1')
two = Foo.new
two.evaluate('a = 2')
one.evaluate('a') => 1
two.evaluate('a') => 2
```

⚠️ Evaluation comes with the usual caveats:

- Avoid modifying any of your predefined identifiers. Remember that in JS,
  as in Ruby, constants are not necessarily constant.
- Never evaluate any code which includes un-checked user data. The Node.js process
  has full read/write access to your filesystem! 💥


## Clean your Rails root

For Rails applications, Nodo enables you to move `node_modules`, `package.json` and
`yarn.lock` into your application's `vendor` folder by setting the `NODE_PATH` in
an initializer:

```ruby
# config/initializers/nodo.rb
Nodo.modules_root = Rails.root.join('vendor', 'node_modules')
```

The rationale for this is NPM modules being external vendor dependencies, which
should not clutter the application root directory.

With this new default, all `yarn` operations should be done after `cd`ing to `vendor`.

This repo provides an [adapted version](https://github.com/mtgrosser/nodo/blob/master/install/yarn.rake)
of the `yarn:install` rake task which will automatically take care of the vendored module location.
