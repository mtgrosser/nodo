module Nodo
  class Script
    attr_reader :code
    
    def initialize(code = nil, &block)
      raise ArgumentError, 'cannot give code when block is given' if code && block
      @code = code || block
    end
  
    def to_js
      js = code.respond_to?(:call) ? code.call : code
      "#{js}\n"
    end
  end
end
