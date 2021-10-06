require_relative 'test_helper'

class NodoTest < Minitest::Test

  def test_function
    nodo = Class.new(Nodo::Core) do
      function :say_hi, "(name) => `Hello ${name}!`"
    end
    assert_equal 'Hello Nodo!', nodo.new.say_hi('Nodo')
  end
  
  def test_require
    nodo = Class.new(Nodo::Core) do
      require :fs
      function :exists_file, "(file) => fs.existsSync(file)"
    end
    assert_equal true, nodo.instance.exists_file(__FILE__)
    assert_equal false, nodo.instance.exists_file('FOOBARFOO')
  end
  
  def test_require_npm
    nodo = Class.new(Nodo::Core) do
      require :uuid
      function :v4, "() => uuid.v4()"
    end
    assert uuid = nodo.new.v4
    assert_equal 36, uuid.size
  end
  
  def test_const
    nodo = Class.new(Nodo::Core) do
      const :FOOBAR, 123
      function :get_const, "() => FOOBAR"
    end
    assert_equal 123, nodo.new.get_const
  end
  
  def test_script
    nodo = Class.new(Nodo::Core) do
      script "var somevar = 99;"
      function :get_somevar, "() => somevar"
    end
    assert_equal 99, nodo.new.get_somevar
  end
  
  def test_async_await
    nodo = Class.new(Nodo::Core) do
      function :do_something, "async () => { return await 'resolved'; }"
    end
    assert_equal 'resolved', nodo.new.do_something
  end
  
  def test_inheritance
    klass = Class.new(Nodo::Core) do
      function :foo, "() => 'superclass'"
    end
    subclass = Class.new(klass) do
      function :bar, "() => { return 'calling' + foo() }"
    end
    subsubclass = Class.new(subclass) do
      function :foo, "() => 'subsubclass'"
    end
    assert_equal 'superclass', klass.new.foo
    assert_equal 'callingsuperclass', subclass.new.bar
    assert_equal 'callingsubsubclass', subsubclass.new.bar
  end
  
  def test_instance_function
    nodo = Class.new(Nodo::Core) do
      function :hello, "() => 'world'"
      class_function :hello
    end
    assert_equal 'world', nodo.hello
  end
  
  def test_syntax
    nodo = Class.new(Nodo::Core) do
      function :test, timeout: nil, code: <<~'JS'
        () => [1, 2, 3]
      JS
    end
    assert_equal [1, 2, 3], nodo.new.test
  end
  
  def test_code_is_required
    assert_raises ArgumentError do
      Class.new(Nodo::Core) do
        function :test, code: <<~'JS'
        JS
      end
    end
  end
  
  def test_timeout
    nodo = Class.new(Nodo::Core) do
      function :sleep, timeout: 1, code: <<~'JS'
        async (sec) => await new Promise(resolve => setTimeout(resolve, sec * 1000))
      JS
    end
    assert_raises Nodo::TimeoutError do
      nodo.new.sleep(2)
    end
  end
  
end
