require 'pathname'
require 'json'
require 'fileutils'
require 'tmpdir'

require_relative 'errors'
require_relative 'core/version'
require_relative 'core/dependency'
require_relative 'core/function'
require_relative 'core/script'
require_relative 'core/constant'
require_relative 'core/client'

module Jass
  class << self
    attr_accessor :modules_root, :env
  end
  self.modules_root = './node_modules'
  self.env = {}
  
  class Core
    SOCKET_NAME = 'jass.sock'
    DEFINE_METHOD = '__jass_define_class__'
    TIMEOUT = 5
    
    @@node_pid = nil
    @@tmpdir = nil
    @@mutex = Mutex.new
    
    class << self
      
      attr_accessor :class_defined
      
      def instance
        @instance ||= new
      end
      
      def class_defined?
        !!class_defined
      end
      
      def clsid
        name || "Class:0x#{object_id.to_s(0x10)}"
      end
      
      %i[dependencies functions constants scripts].each do |attr|
        define_method "#{attr}=" do |value|
          instance_variable_set :"@#{attr}", value
        end
        define_method "#{attr}" do
          instance_variable_get(:"@#{attr}") || instance_variable_set(:"@#{attr}", [])
        end
      end
      
      def require(*mods)
        deps = mods.last.is_a?(Hash) ? mods.pop : {}
        mods = mods.map { |m| [m, m] }.to_h
        self.dependencies = dependencies + mods.merge(deps).map { |name, package| Dependency.new(name, package) }
      end

      def function(name, code)
        self.functions = functions + [Function.new(name, code)]
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
          global.jass = require(#{jass_js})
          
          const socket = process.argv[1];
          if (!socket) {
            process.stderr.write('Socket path is required\\n');
            process.exit(1);
          }
          
          const shutdown = () => {
            jass.core.close(() => { process.exit(0) });
          };

          process.on('SIGINT', shutdown);
          process.on('SIGTERM', shutdown);

          jass.core.run(socket);
        JS
      end

      def generate_class_code
        <<~JS
          (() => {
            const __jass_log = jass.log;
            const __jass_klass__ = {};
            #{dependencies.map(&:to_js).join}
            #{constants.map(&:to_js).join}
            #{functions.map(&:to_js).join}
            #{scripts.map(&:to_js).join}
            return __jass_klass__;
          })()
        JS
      end

      protected

      def finalize(pid, tmpdir)
        proc do
          Process.kill(:SIGTERM, pid)
          Process.wait(pid)
          FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir)
        end
      end
      
      private
      
      def jass_js
        Pathname.new(__FILE__).dirname.join('jass.js').to_s.to_json
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
      @@tmpdir = Pathname.new(Dir.mktmpdir('jass'))
      env = Jass.env.merge('NODE_PATH' => Jass.modules_root.to_s)
      @@node_pid = Process.spawn(env, 'node', '-e', self.class.generate_core_code, '--', socket_path.to_s)
      ObjectSpace.define_finalizer(self, self.class.send(:finalize, node_pid, tmpdir))
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
      request = Net::HTTP::Post.new("/#{clsid}/#{method}", 'Content-Type': 'application/json')
      request.body = JSON.dump(args)
      client = Client.new("unix://#{socket_path}")
      response = client.request(request)
      raise Error if response.is_a?(Net::HTTPClientError) # TODO
      JSON.parse(response.body.force_encoding('UTF-8'))
    rescue Errno::EPIPE, IOError
      # TODO(bouk): restart or something? If this happens the process is completely broken
      raise Error, 'Node process failed'
    end
    
  end
end
