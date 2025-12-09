module Nodo
  class Error < StandardError; end
  class TimeoutError < Error; end
  class CallError < Error; end
  class ClassError < Error
    def initialize(method = nil)
      super("Cannot call method `#{method}' on Nodo::Core, use subclass instead")
    end
  end
  
  class JavaScriptError < Error
    attr_reader :attributes
    
    def initialize(attributes = {}, function = nil)
      @attributes = attributes || {}
      if backtrace = generate_backtrace(attributes['stack'])
        backtrace.unshift function.source_location if function && function.source_location
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
      message = "#{attributes['message'] || attributes['name'] || 'Unknown error'}"
      message << format_location(attributes['loc'])
    end
    
    def format_location(loc)
      return '' unless loc
      loc.inject(+' in') { |s, (key, value)| s << " #{key}: #{value}" }
    end
  end
  
  class DependencyError < JavaScriptError
    private
    
    def generate_message
      message = "#{attributes['message'] || attributes['name'] || 'Dependency error'}\n"
      message << "The specified dependency '#{attributes['nodo_dependency']}' could not be loaded. "
      message << "Run 'yarn add #{attributes['nodo_dependency']}' to install it.\n"
    end
  end
end
