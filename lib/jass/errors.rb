module Jass
  class Error < StandardError; end
  
  class JavaScriptError < Error
    attr_reader :attributes
    
    def initialize(attributes = {})
      @attributes = attributes || {}
      if stack = attributes['stack']
        set_backtrace stack.split("\n")
      end
    end
    
    def to_s
      generate_message
    end
    
    private
    
    def generate_message
      message = "#{attributes['message'] || 'Unknown error'}"
      if loc = attributes['loc']
        message << loc.inject(' in') { |s, (key, value)| s << " #{key}: #{value}" }
      end
    end
  end
  
  class DependencyError < JavaScriptError; end
end
