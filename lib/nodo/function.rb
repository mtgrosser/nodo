module Nodo
  class Function
    attr_reader :name, :code, :source_location, :timeout
  
    def initialize(name, code, source_location, timeout)
      @name, @code, @source_location, @timeout = name, code, source_location, timeout
    end
  
    def to_js
      "const #{name} = __nodo_klass__.#{name} = (#{code});\n"
    end
  end
end
