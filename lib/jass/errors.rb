module Jass
  class Error < StandardError; end
  class TimeoutError < Error; end
  
  class JavaScriptError < Error
    attr_reader :attributes
    
    def initialize(attributes = {})
      @attributes = attributes || {}
      if backtrace = generate_backtrace(attributes['stack'])
        set_backtrace backtrace
      end
      @message = generate_message
    end
    
    def to_s
      @message
    end
    
    private

    # "filename:lineNo: in `method''' or “filename:lineNo.''
     
    def generate_backtrace(stack)
      backtrace = []
      if stack and lines = stack.split("\n")
        lines.shift
        lines.each do |line|
          if match = line.match(/\A *at (?<call>.+) \((?<src>.*):(?<line>\d+):(?<column>\d+)\)/)
            backtrace << "#{match[:src]}:#{match[:line]}:in `#{match[:call]}'"
          end
        end
      end
      backtrace unless backtrace.empty?
    end
    
    def generate_message
      message = "#{attributes['message'] || 'Unknown error'}"
      if loc = attributes['loc']
        message << loc.inject(' in') { |s, (key, value)| s << " #{key}: #{value}" }
      end
      message
    end
  end
  
  class DependencyError < JavaScriptError; end
end
