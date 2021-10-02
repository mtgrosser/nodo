module Nodo
  class Constant
    attr_reader :name, :value
  
    def initialize(name, value)
      @name, @value = name, value
    end

    def to_js
      "const #{name} = #{value.to_json};\n"
    end
  end
end
