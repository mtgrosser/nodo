module Nodo
  class Function
    attr_reader :name, :code, :source_location
  
    def initialize(name, code, source_location)
      @name, @code, @source_location = name, code, source_location
    end
  
    def to_js
      "const #{name} = __nodo_klass__.#{name} = (#{code});\n"
    end
  end
end
