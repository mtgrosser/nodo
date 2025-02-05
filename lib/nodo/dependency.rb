module Nodo
  class Dependency
    attr_reader :name, :package, :type

    def initialize(name, package, type:)
      @name, @package, @type = name, package, type
    end

    def to_js
      case type
      when :cjs then to_cjs
      when :esm then to_esm
      else raise "Unknown dependency type: #{type}"
      end
    end

    private

    def to_cjs
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

    def to_esm
      <<~JS
        const #{name} = __nodo_klass__.#{name} = await (async () => {
          try {
            return await nodo.import(#{package.to_json});
          } catch(e) {
            e.nodo_dependency = #{package.to_json};
            throw e;
          }
        })();
      JS
    end
  end
end
