class Jass::Core::Function
  attr_reader :name, :code
  
  def initialize(name, code)
    @name, @code = name, code
  end
  
  def to_js
    "const #{name} = __jass_klass__.#{name} = (#{code});\n"
  end
end
