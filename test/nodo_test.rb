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
  
  def test_deferred_script_definition_by_block
    nodo = Class.new(Nodo::Core) do
      singleton_class.attr_accessor :value
      script do
        "var somevar = #{value.to_json};"
      end
      function :get_somevar, "() => somevar"
    end
    nodo.value = 123
    assert_equal 123, nodo.new.get_somevar
  end
  
  def test_cannot_define_both_code_and_block_for_script
    assert_raises ArgumentError do
      Class.new(Nodo::Core) do
        script 'var foo;' do
          'var bar;'
        end
      end
    end
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
  
  def test_deferred_function_definition_by_block
    nodo = lambda do
      Class.new(Nodo::Core) do
        singleton_class.attr_accessor :value

        function :test, timeout: nil do
          <<~JS
            () => [1, #{value}, 3]
          JS
        end
      end
    end
    assert_equal [1, nil, 3], nodo.().new.test
    assert_equal [1, 222, 3], nodo.().tap { |klass| klass.value = 222 }.new.test
  end
  
  def test_cannot_define_both_code_and_block_for_function
    assert_raises ArgumentError do
      Class.new(Nodo::Core) do
        function :test, code: '() => true' do
          '() => false'
        end
      end
    end
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
  
  def test_internal_method_names_are_reserved
    assert_raises ArgumentError do
      Class.new(Nodo::Core) do
        function :tmpdir, code: "() => '.'"
      end
    end
  end
  
  def test_logging
    with_logger test_logger do
      assert_raises(Nodo::JavaScriptError) do
        Class.new(Nodo::Core) { function :bork, code: "() => {;;;" }.new
      end
      assert_equal 1, Nodo.logger.errors.size
      assert_match /Nodo::JavaScriptError/, Nodo.logger.errors.first
    end
  end
  
  def test_dependency_error
    with_logger nil do
      nodo = Class.new(Nodo::Core) do
        require 'foobarfoo'
      end
      assert_raises Nodo::DependencyError do
        nodo.new
      end
    end
  end
  
  def test_evaluation
    assert_equal 8, Class.new(Nodo::Core).new.evaluate('3 + 5')
  end
  
  def test_evaluation_can_access_constants
    nodo = Class.new(Nodo::Core) do
      const :FOO, 'bar'
    end
    assert_equal 'barfoo', nodo.new.evaluate('FOO + "foo"')
  end
  
  def test_evaluation_can_access_functions
    nodo = Class.new(Nodo::Core) do
      function :hello, code: "(name) => `Hello ${name}!`"
    end
    assert_equal 'Hello World!', nodo.new.evaluate('hello("World")')
  end
  
  def test_evaluation_contexts_properties_are_shared_between_instances
    nodo = Class.new(Nodo::Core) do
      const :LIST, []
      function :list, code: "() => LIST"
    end
    one = nodo.new
    two = nodo.new
    one.evaluate("LIST.push('one')")
    two.evaluate("LIST.push('two')")
    assert_equal %w[one two], one.evaluate('list()')
    assert_equal %w[one two], two.evaluate('list()')
  end
  
  def test_evaluation_contexts_locals_are_separated_by_instance
    nodo = Class.new(Nodo::Core)
    one = nodo.new
    two = nodo.new
    one.evaluate("const list = []; list.push('one')")
    two.evaluate("const list = []; list.push('two')")
    assert_equal %w[one], one.evaluate('list')
    assert_equal %w[two], two.evaluate('list')
  end
  
  def test_evaluation_can_require_on_its_own
    nodo = Class.new(Nodo::Core).new
    nodo.evaluate('const uuid = require("uuid")')
    uuid = nodo.evaluate('uuid.v4()')
    assert_uuid uuid
  end
  
  def test_evaluation_can_access_requires
    nodo = Class.new(Nodo::Core) { require :uuid }
    uuid = nodo.new.evaluate('uuid.v4()')
    assert_uuid uuid
  end
  
  def test_cannot_instantiate_core
    assert_raises Nodo::ClassError do
      Nodo::Core.new
    end
  end
  
  def test_dynamic_imports_in_functions
    klass = Class.new(Nodo::Core) do
      function :v4, <<~JS
        async () => {
          const uuid = await nodo.import('uuid');
          return await uuid.v4()
        }
      JS
    end
    nodo = klass.new
    assert_uuid uuid_1 = nodo.v4
    assert_uuid uuid_2 = nodo.v4
    assert uuid_1 != uuid_2
  end
  
  def test_dynamic_imports_in_evaluation
    nodo = Class.new(Nodo::Core)
    uuid = nodo.new.evaluate("nodo.import('uuid').then((uuid) => uuid.v4()).catch((e) => null)")
    assert_uuid uuid
  end
  
  private
  
  def test_logger
    Object.new.instance_exec do
      def errors; @errors ||= []; end
      def error(msg); errors << msg; end
      self
    end
  end
  
  def with_logger(logger)
    prev_logger = Nodo.logger
    Nodo.logger = logger
    yield
  ensure
    Nodo.logger = prev_logger
  end
  
  def assert_uuid(obj)
    assert_match /\A\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\z/, obj
  end

end
