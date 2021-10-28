module Nodo
  class Function
    attr_reader :name, :code, :source_location, :timeout
  
    def initialize(name, code, source_location, timeout, &block)
      raise ArgumentError, 'cannot give code when block is given' if code && block
      code = code.strip if code
      raise ArgumentError, 'function code is required' if '' == code
      raise ArgumentError, 'code is required' unless code || block
      @name, @code, @source_location, @timeout = name, code || block, source_location, timeout
    end
  
    def to_js
      js = code.respond_to?(:call) ? code.call.strip : code
      "const #{name} = __nodo_klass__.#{name} = (#{js});\n"
    end
  end
end
