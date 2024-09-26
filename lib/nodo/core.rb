module Nodo
  class Core
    SOCKET_NAME = 'nodo.sock'
    DEFINE_METHOD = '__nodo_define_class__'.freeze
    EVALUATE_METHOD = '__nodo_evaluate__'.freeze
    GC_METHOD = '__nodo_gc__'.freeze
    INTERNAL_METHODS = [DEFINE_METHOD, EVALUATE_METHOD, GC_METHOD].freeze
    LAUNCH_TIMEOUT = 5
    ARRAY_CLASS_ATTRIBUTES = %i[dependencies constants scripts].freeze
    HASH_CLASS_ATTRIBUTES = %i[functions].freeze
    CLASS_ATTRIBUTES = (ARRAY_CLASS_ATTRIBUTES + HASH_CLASS_ATTRIBUTES).freeze

    @@node_pid = nil
    @@tmpdir = nil
    @@mutex = Mutex.new
    @@exiting = nil

    class << self
      extend Forwardable

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
        protected "#{attr}="
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

      def generate_core_code
        <<~JS
          global.nodo = require(#{nodo_js});

          const socket = process.argv[1];
          if (!socket) {
            process.stderr.write('Socket path is required\\n');
            process.exit(1);
          }

          process.title = `nodo-core ${socket}`;

          const shutdown = () => {
            nodo.core.close(() => { process.exit(0) });
          };

          // process.on('SIGINT', shutdown);
          process.on('SIGTERM', shutdown);

          nodo.core.run(socket);
        JS
      end

      def generate_class_code
        <<~JS
          (() => {
            const __nodo_klass__ = { nodo: global.nodo };
            #{dependencies.map(&:to_js).join}
            #{constants.map(&:to_js).join}
            #{functions.values.map(&:to_js).join}
            #{scripts.map(&:to_js).join}
            return __nodo_klass__;
          })()
        JS
      end

      protected

      def finalize_context(context_id)
        proc do
          if not @@exiting and core = Nodo::Core.instance
            core.send(:call_js_method, GC_METHOD, context_id)
          end
        end
      end

      private

      def require(*mods)
        deps = mods.last.is_a?(Hash) ? mods.pop : {}
        mods = mods.map { |m| [m, m] }.to_h
        self.dependencies = dependencies + mods.merge(deps).map { |name, package| Dependency.new(name, package) }
      end

      def function(name, _code = nil, timeout: Nodo.timeout, code: nil, &block)
        raise ArgumentError, "reserved method name #{name.inspect}" if reserved_method_name?(name)
        loc = caller_locations(1, 1)[0]
        source_location = "#{loc.path}:#{loc.lineno}: in `#{name}'"
        self.functions = functions.merge(name => Function.new(name, _code || code, source_location, timeout, &block))
        define_method(name) { |*args| call_js_method(name, args) }
      end

      def class_function(*methods)
        singleton_class.def_delegators(:instance, *methods)
      end

      def const(name, value)
        self.constants = constants + [Constant.new(name, value)]
      end

      def script(code = nil, &block)
        self.scripts = scripts + [Script.new(code, &block)]
      end

      def nodo_js
        Pathname.new(__FILE__).dirname.join('nodo.cjs').to_s.to_json
      end

      def reserved_method_name?(name)
        Nodo::Core.method_defined?(name, false) || Nodo::Core.private_method_defined?(name, false) || name.to_s == DEFINE_METHOD
      end
    end

    def initialize
      raise ClassError, :new if self.class == Nodo::Core
      @@mutex.synchronize do
        ensure_process_is_spawned
        wait_for_socket
        ensure_class_is_defined
      end
    end

    def evaluate(code)
      ensure_context_is_defined
      call_js_method(EVALUATE_METHOD, code)
    end

    private

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

    def context_defined?
      @context_defined
    end

    def log_exception(e)
      return unless logger = Nodo.logger
      message = "\n#{e.class} (#{e.message})"
      message << ":\n\n#{e.backtrace.join("\n")}" if e.backtrace
      logger.error message
    end

    def ensure_process_is_spawned
      return if node_pid
      spawn_process
    end

    def ensure_class_is_defined
      return if self.class.class_defined?
      call_js_method(DEFINE_METHOD, self.class.generate_class_code)
      self.class.class_defined = true
    end

    def ensure_context_is_defined
      return if context_defined?
      @@mutex.synchronize do
        call_js_method(EVALUATE_METHOD, '')
        ObjectSpace.define_finalizer(self, self.class.send(:finalize_context, self.object_id))
        @context_defined = true
      end
    end

    def spawn_process
      @@tmpdir = Pathname.new(Dir.mktmpdir('nodo'))
      env = Nodo.env.merge('NODE_PATH' => Nodo.modules_root.to_s)
      env['NODO_DEBUG'] = '1' if Nodo.debug
      @@node_pid = Process.spawn(env, Nodo.binary, '-e', self.class.generate_core_code, '--', socket_path.to_s, err: :out)
      at_exit do
        @@exiting = true
        Process.kill(:SIGTERM, node_pid) rescue Errno::ECHILD
        Process.wait(node_pid) rescue Errno::ECHILD
        FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir)
      end
    end

    def wait_for_socket
      start = Time.now
      socket = nil
      while Time.now - start < LAUNCH_TIMEOUT
        begin
          break if socket = UNIXSocket.new(socket_path.to_s)
        rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::ENOTDIR
          Kernel.sleep(0.2)
        end
      end
      socket.close if socket
      raise TimeoutError, "could not connect to socket #{socket_path}" unless socket
    end

    def call_js_method(method, args)
      raise CallError, 'Node process not ready' unless node_pid
      raise CallError, "Class #{clsid} not defined" unless self.class.class_defined? || INTERNAL_METHODS.include?(method)
      function = self.class.functions[method]
      raise NameError, "undefined function `#{method}' for #{self.class}" unless function || INTERNAL_METHODS.include?(method)
      context_id = case method
        when DEFINE_METHOD then 0
        when GC_METHOD then args.first
      else
        object_id
      end
      request = Net::HTTP::Post.new("/#{clsid}/#{context_id}/#{method}", 'Content-Type': 'application/json')
      request.body = JSON.dump(args)
      client = Client.new("unix://#{socket_path}")
      client.read_timeout = function&.timeout || Nodo.timeout
      response = client.request(request)
      if response.is_a?(Net::HTTPOK)
        parse_response(response)
      else
        handle_error(response, function)
      end
    rescue Net::ReadTimeout
      raise TimeoutError, "function call #{self.class}##{method} timed out"
    rescue Errno::EPIPE, IOError
      # TODO: restart or something? If this happens the process is completely broken
      raise Error, 'Node process failed'
    end

    def handle_error(response, function)
      if response.body
        result = parse_response(response)
        error = if result.is_a?(Hash) && result['error'].is_a?(Hash)
          attrs = result['error']
          (attrs['nodo_dependency'] ? DependencyError : JavaScriptError).new(attrs, function)
        end
      end
      error ||= CallError.new("Node returned #{response.code}")
      log_exception(error)
      raise error
    end

    def parse_response(response)
      data = response.body.force_encoding('UTF-8')
      JSON.parse(data) unless data == ''
    end

    def with_tempfile(name)
      ext = File.extname(name)
      result = nil
      Tempfile.create([File.basename(name, ext), ext], tmpdir) do |file|
        result = yield(file)
      end
      result
    end

  end
end
