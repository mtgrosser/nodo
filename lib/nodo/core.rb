module Nodo
  class Core
    SOCKET_NAME = 'nodo.sock'
    DEFINE_METHOD = '__nodo_define_class__'
    TIMEOUT = 5
    ARRAY_CLASS_ATTRIBUTES = %i[dependencies constants scripts].freeze
    HASH_CLASS_ATTRIBUTES = %i[functions].freeze
    CLASS_ATTRIBUTES = (ARRAY_CLASS_ATTRIBUTES + HASH_CLASS_ATTRIBUTES).freeze
    
    @@node_pid = nil
    @@tmpdir = nil
    @@mutex = Mutex.new
    
    class << self
      
      attr_accessor :class_defined
      
      def inherited(subclass)
        CLASS_ATTRIBUTES.each do |attr|
          subclass.send "#{attr}=", send(attr).dup
        end
      end

      def instance
        @instance ||= new
      end
      
      def class_defined?
        !!class_defined
      end
      
      def clsid
        name || "Class:0x#{object_id.to_s(0x10)}"
      end
      
      CLASS_ATTRIBUTES.each do |attr|
        define_method "#{attr}=" do |value|
          instance_variable_set :"@#{attr}", value
        end
      end
      
      ARRAY_CLASS_ATTRIBUTES.each do |attr|
        define_method "#{attr}" do
          instance_variable_get(:"@#{attr}") || instance_variable_set(:"@#{attr}", [])
        end
      end
      
      HASH_CLASS_ATTRIBUTES.each do |attr|
        define_method "#{attr}" do
          instance_variable_get(:"@#{attr}") || instance_variable_set(:"@#{attr}", {})
        end
      end
      
      def require(*mods)
        deps = mods.last.is_a?(Hash) ? mods.pop : {}
        mods = mods.map { |m| [m, m] }.to_h
        self.dependencies = dependencies + mods.merge(deps).map { |name, package| Dependency.new(name, package) }
      end

      def function(name, code)
        self.functions = functions.merge(name => Function.new(name, code, caller.first))
        define_method(name) { |*args| call_js_method(name, args) }
      end
      
      def const(name, value)
        self.constants = constants + [Constant.new(name, value)]
      end
      
      def script(code)
        self.scripts = scripts + [Script.new(code)]
      end

      def generate_core_code
        <<~JS
          global.nodo = require(#{nodo_js});
          
          const socket = process.argv[1];
          if (!socket) {
            process.stderr.write('Socket path is required\\n');
            process.exit(1);
          }
          
          const shutdown = () => {
            nodo.core.close(() => { process.exit(0) });
          };

          process.on('SIGINT', shutdown);
          process.on('SIGTERM', shutdown);

          nodo.core.run(socket);
        JS
      end

      def generate_class_code
        <<~JS
          (() => {
            const __nodo_log = nodo.log;
            const __nodo_klass__ = {};
            #{dependencies.map(&:to_js).join}
            #{constants.map(&:to_js).join}
            #{functions.values.map(&:to_js).join}
            #{scripts.map(&:to_js).join}
            return __nodo_klass__;
          })()
        JS
      end

      protected

      def finalize(pid, tmpdir)
        proc do
          Process.kill(:SIGTERM, pid) rescue Errno::ECHILD
          Process.wait(pid) rescue Errno::ECHILD
          FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir)
        end
      end
      
      private
      
      def nodo_js
        Pathname.new(__FILE__).dirname.join('nodo.js').to_s.to_json
      end
    end
    
    def initialize
      @@mutex.synchronize do
        ensure_process_is_spawned
        wait_for_socket
        ensure_class_is_defined
      end
    end
    
    def node_pid
      @@node_pid
    end
    
    def tmpdir
      @@tmpdir
    end

    def socket_path
      tmpdir && tmpdir.join(SOCKET_NAME)
    end
    
    def clsid
      self.class.clsid
    end
    
    def ensure_process_is_spawned
      return if node_pid
      spawn_process
    end
    
    def ensure_class_is_defined
      return if self.class.class_defined?
      call_js_method(DEFINE_METHOD, self.class.generate_class_code)
      self.class.class_defined = true
#    rescue => e
 #     raise Error, e.message
    end

    def spawn_process
      @@tmpdir = Pathname.new(Dir.mktmpdir('nodo'))
      env = Nodo.env.merge('NODE_PATH' => Nodo.modules_root.to_s)
      @@node_pid = Process.spawn(env, Nodo.binary, '-e', self.class.generate_core_code, '--', socket_path.to_s, err: :out)
      ObjectSpace.define_finalizer(self, Core.send(:finalize, node_pid, tmpdir))
    end
    
    def wait_for_socket
      start = Time.now
      until socket_path.exist?
        raise TimeoutError, "socket #{socket_path} not found" if Time.now - start > TIMEOUT
        sleep(0.2)
      end
    end

    def call_js_method(method, args)
      raise CallError, 'Node process not ready' unless node_pid
      raise CallError, "Class #{clsid} not defined" unless self.class.class_defined? || method == DEFINE_METHOD
      function = self.class.functions[method]
      raise NameError, "undefined function `#{method}' for #{self.class}" unless function || method == DEFINE_METHOD
      request = Net::HTTP::Post.new("/#{clsid}/#{method}", 'Content-Type': 'application/json')
      request.body = JSON.dump(args)
      client = Client.new("unix://#{socket_path}")
      response = client.request(request)
      if response.is_a?(Net::HTTPOK)
        parse_response(response)
      else
        handle_error(response, function)
      end
    rescue Errno::EPIPE, IOError
      # TODO: restart or something? If this happens the process is completely broken
      raise Error, 'Node process failed'
    end
    
    def handle_error(response, function)
      if response.body
        result = parse_response(response)
        raise JavaScriptError.new(result['error'], function) if result.is_a?(Hash) && result.key?('error')
      end
      raise CallError, "Node returned #{response.code}"
    end
    
    def parse_response(response)
      JSON.parse(response.body.force_encoding('UTF-8'))
    end
    
  end
end
