module Jass
  class Script
    attr_reader :code
    
    def initialize(code)
      @code = code
    end
  
    def to_js
      "#{code}\n"
    end
   
  end
end
