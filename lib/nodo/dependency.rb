module Nodo
  class Dependency
    attr_reader :name, :package
    
    def initialize(name, package)
      @name, @package = name, package
    end
  
    def to_js
      <<~JS
        const #{name} = __nodo_klass__.#{name} = (() => {
          try {
            return require(#{package.to_json});
          } catch(e) {
            e.nodo_dependency = #{package.to_json};
            throw e;
          }
        })();
      JS
    end
  end
end
