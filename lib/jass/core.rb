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
    attr_accessor :modules_root
  end
  
  class Core
    SOCKET_NAME = 'jass.sock'
    TIMEOUT = 5
    
    attr_reader :root, :env, :tmpdir
    
    class << self
      
      def instance
        @instance ||= new
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

      def generate_code
        <<~JS
          
          function __jass_render_error(e) {
            let errInfo = {};
            if (e instanceof Error) {
              errInfo.name = e.name;
              Object.getOwnPropertyNames(e).reduce((obj, prop) => { obj[prop] = e[prop]; return obj }, errInfo);
            } else {
              errInfo.name = e.toString();
            }
            return JSON.stringify({ error: errInfo });
          }
          
          function __jass_respond_with_error(res, code, name) {
            res.statusCode = code;
            const rendered = __jass_render_error(name);
            __jass_log(`Error ${code} ${rendered}`);
            res.end(rendered, 'utf8');
          }
          
          function __jass_log(message) {
            // __jass_fs.appendFileSync('log/jass.log', `${message}\\n`);
            // console.log(`[Jass] ${message}`);
          }
          
          // TODO: prefix internal identifiers
          const __jass_http = require('http');
          const __jass_path = require('path');
          const __jass_fs = require('fs');
          const __jass_performance = require('perf_hooks').performance;
          
          const __jass_tmpdir = process.argv[1];
          const __jass_socket = __jass_path.join(__jass_tmpdir, '#{SOCKET_NAME}');
          
          try {
            #{dependencies.map(&:to_js).join}
          } catch (e) {
            process.stderr.write(e.toString());
            process.stderr.write(`\\n`);
            process.exit(1);
          }
          
          __jass_log('[Jass] Starting up... \\n');
          
          #{constants.map(&:to_js).join}
          
          const __jass_methods = {};
          #{functions.map(&:to_js).join}
          
          try {
            #{scripts.map(&:to_js).join}
          } catch (e) {
            process.stderr.write(e.toString());
            process.stderr.write(`\\n`);
            process.exit(1);
          }
          
          const __jass_server = __jass_http.createServer((req, res) => {
            const start = __jass_performance.now();

            res.setHeader('Content-Type', 'application/json');
            __jass_log(`POST ${req.url}`);
  
            if (req.method !== 'POST' || !req.url.startsWith('/')) {
              return __jass_respond_with_error(res, 405, 'Method Not Allowed');
            }
  
            const method = req.url.substring(1);
  
            if (!req.url.startsWith('/') || !__jass_methods.hasOwnProperty(method)) {
              return __jass_respond_with_error(res, 404, 'Not Found');
            }
  
            let body = '';

            req.on('data', (data) => { body += data; });

            req.on('end', () => {
              let input, result;

              try {
                input = JSON.parse(body);
              } catch (e) {
                return __jass_respond_with_error(res, 400, 'Bad Request');
              }

              try {
                Promise.resolve(__jass_methods[method].apply(null, input)).then(function (result) {
                  res.statusCode = 200;
                  res.end(JSON.stringify(result), 'utf8');
                  __jass_log(`Completed 200 OK in ${(__jass_performance.now() - start).toFixed(2)}ms\\n`);
                }).catch(function(error) {
                  __jass_respond_with_error(res, 500, error);
                });
              } catch(error) {
                return __jass_respond_with_error(res, 500, error);
              }
              
            });
          });
          
          //server.maxConnections = 64;
          __jass_server.listen(__jass_socket, () => {
            __jass_log(`server ready, listening on ${__jass_socket} (max connections: ${__jass_server.maxConnections})\\n`);
          });

          let closing;

          const shutdown = () => {
            __jass_log("Shutting down\\n");
            if (!closing) {
              closing = true;
              __jass_server.close(() => { process.exit(0) });
            }
          };

          process.on('SIGINT', shutdown);
          process.on('SIGTERM', shutdown);
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
    end

    def initialize(root = Jass.modules_root, env = {})
      @root = root || './node_modules'
      @env = env || {}
      @env['NODE_PATH'] ||= root.to_s
      @mutex = Mutex.new
    end

    def node_pid
      @node_pid
    end

    private
    
    def socket_path
      tmpdir && tmpdir.join(SOCKET_NAME)
    end
    
    def ensure_process_is_spawned
      return if node_pid
      spawn_process
    end

    def spawn_process
      @tmpdir = Pathname.new(Dir.mktmpdir('jass'))
      @node_pid = Process.spawn(env, 'node', '-e', self.class.generate_code, '--', @tmpdir.to_s)
      ObjectSpace.define_finalizer(self, self.class.send(:finalize, node_pid, tmpdir))
    end
    
    def wait_for_socket
      start = Time.now
      until socket_path.exist?
        raise Jass::TimeoutError, "socket #{socket_path} not found" if Time.now - start > TIMEOUT
        sleep(0.2)
      end
    end

    def call_js_method(method, args)
      @mutex.synchronize do
        ensure_process_is_spawned
        wait_for_socket
      end
      request = Net::HTTP::Post.new("/#{method}", 'Content-Type': 'application/json')
      request.body = JSON.dump(args)
      client = Client.new("unix://#{socket_path}")
      response = client.request(request)
      raise Jass::Error if response.is_a?(Net::HTTPClientError) # TODO
      JSON.parse(response.body.force_encoding('UTF-8'))
    rescue Errno::EPIPE, IOError
      # TODO(bouk): restart or something? If this happens the process is completely broken
      raise Jass::Error, "Node process failed:\n#{@node_stderr.read}"
    end
    
  end
end
