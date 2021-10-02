require_relative 'test_helper'

class JassCoreTest < Minitest::Test

  def test_function
    jass = Class.new(Jass::Core) do
      function :say_hi, "(name) => `Hello ${name}!`"
    end
    assert_equal 'Hello Jass!', jass.new.say_hi('Jass')
  end
  
  def test_require
    jass = Class.new(Jass::Core) do
      require :fs
      function :exists_file, "(file) => fs.existsSync(file)"
    end
    assert_equal true, jass.instance.exists_file(__FILE__)
    assert_equal false, jass.instance.exists_file('FOOBARFOO')
  end
  
  def test_const
    jass = Class.new(Jass::Core) do
      const :FOOBAR, 123
      function :get_const, "() => FOOBAR"
    end
    assert_equal 123, jass.new.get_const
  end
  
  def test_script
    jass = Class.new(Jass::Core) do
      script "var somevar = 99;"
      function :get_somevar, "() => somevar"
    end
    assert_equal 99, jass.new.get_somevar
  end
  
  def test_async_await
    jass = Class.new(Jass::Core) do
      function :do_something, "async () => { return await 'resolved'; }"
    end
    assert_equal 'resolved', jass.new.do_something
  end
  
end
