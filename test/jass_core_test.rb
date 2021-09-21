require_relative 'test_helper'

class JassCoreTest < Minitest::Test
  def setup
    @jass = Class.new(Jass::Core) do
      function :say_hi, <<~JS
        (name) => {
          return `Hello ${name}!`;
        }
      JS
    end
  end
  
  def test_jass
    assert_equal 'Hello Jass!', @jass.new.say_hi('Jass')
  end
end
