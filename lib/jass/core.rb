require 'set'
require 'pathname'
require 'open3'
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
      
      def dependency(deps)
        self.dependencies = dependencies + deps.map { |name, package| Dependency.new(name, package) }
      end

      def function(name, code)
        self.functions = functions + [Function.new(name, code)]
        define_method(name) { |*args| call_js_method(name, args) }
      end
      
      def constant(name, value)
        self.constants = constants + [Constant.new(name, value)]
      end
      
      def script(code)
        self.scripts = scripts + [Script.new(code)]
      end

      def generate_code
        <<~JS
        
          class JassRuntimeError extends Error {
            constructor(message) {
              super(message);
              this.name = "JassRuntimeError";
            }
          }
/*
          function __jass_handle_error(error) {
            var errInfo = {};
            if (error instanceof Error) {
              errInfo.name = error.name;
              Object.getOwnPropertyNames(error).reduce((obj, prop) => { obj[prop] = error[prop]; return obj }, errInfo);
            } else {
              errInfo.name = error.toString();
            }
            process.stdout.write(`${JSON.stringify(['err', errInfo])}\\n`);
          }
*/          
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

          /*function __jass_render_error(error) {
            let errInfo = { name: error || 'RUNTIME_ERROR' }
            return JSON.stringify({ error: errInfo });
          }*/

          function __jass_respond_with_error(res, code, name) {
            res.statusCode = code;
            const rendered = __jass_render_error(name);
            __jass_log(`Error ${code} ${rendered}`);
            res.end(rendered);
          }
          
          function __jass_log(message) {
            // fs.appendFileSync('log/jass.log', `${message}\\n`);
            console.log(message);
          }
          
          // TODO: prefix internal identifiers
          const http = require('http');
          const path = require('path');
          const fs = require('fs');
          const performance = require('perf_hooks').performance;
          
          const tmpdir = process.argv[1];
          const socket = path.join(tmpdir, '#{SOCKET_NAME}');
          
          try {
            #{dependencies.map(&:to_js).join}
          } catch (e) {
            // STDIN __jass_handle_error(e);
            process.stderr.write(e.toString());
            process.stderr.write(`\\n`);
            process.exit(1);
          }
          
          process.stdout.write('Starting up... ');
          
          #{constants.map(&:to_js).join}
          
          const __jass_methods = {};
          #{functions.map(&:to_js).join}
          
          try {
            #{scripts.map(&:to_js).join}
          } catch (e) {
            // STDIN __jass_handle_error(e);
            process.stderr.write(e.toString());
            process.stderr.write(`\\n`);
            process.exit(1);
          }
          
          const server = http.createServer((req, res) => {
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
                  res.end(JSON.stringify(result));
                  __jass_log(`Completed 200 OK`);
                }).catch(function(error) {
                  __jass_respond_with_error(res, 500, error);
                });
              } catch(error) {
                return __jass_respond_with_error(res, 500, error);
              }
              
            });
          });
          
          //server.maxConnections = 64;
          server.listen(socket, () => {
            __jass_log(`server ready, listening on ${socket} (max connections: ${server.maxConnections})\\n`);
          });

          let closing;

          const shutdown = () => {
            __jass_log("Shutting down\\n");
            if (!closing) {
              closing = true;
              server.close(() => { process.exit(0) });
            }
          };

          process.on('SIGINT', shutdown);
          process.on('SIGTERM', shutdown);
        JS
      end

      protected

      def finalize(process_data, tmpdir)
        proc do
          stdin, stdout, stderr, process_thread = process_data
          stdin.close
          stdout.close
          stderr.close
          Process.kill(0, process_thread.pid)
          process_thread.value
          FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir)
        end
      end
    end

    def initialize(root = Jass.modules_root, env = {})
      @root = root || '.'
      @env = env || {}
      @env['NODE_PATH'] ||= root.to_s
      @mutex = Mutex.new
    end

    def pid
      @node_process_thread && @node_process_thread.pid
    end

    private
    
    def socket_path
      tmpdir && tmpdir.join(SOCKET_NAME)
    end
    
    def ensure_process_is_spawned
      return if @node_process_thread
      spawn_process
    end

    def spawn_process
      @tmpdir = Pathname.new(Dir.mktmpdir('jass'))
      process_data = Open3.popen3(env, 'node', '-e', self.class.generate_code, '--', @tmpdir.to_s)
      @node_stdin, @node_stdout, @node_stderr, @node_process_thread = process_data
      #ensure_packages_are_initiated(*process_data)
      ObjectSpace.define_finalizer(self, self.class.send(:finalize, process_data, @tmpdir))
    end
    
    def wait_for_socket
      start = Time.now
      until socket_path.exist?
        raise Jass::TimeoutError, "socket #{socket_path} not found" if Time.now - start > TIMEOUT
        sleep(0.2)
      end
    end

    #def ensure_packages_are_initiated(stdin, stdout, stderr, process_thread)
    #  input = stdout.gets
    #  raise Jass::Error, "Failed to instantiate Node process:\n#{stderr.read}" if input.nil?
    #  #unless input.include?('server ready')
    #  #  stdout.close
    #  #  stderr.close
    #  #  process_thread.join
    #  #  raise Jass::Error
    #  #end
    #end<

    def call_js_method(method, args)
      @mutex.synchronize do
        ensure_process_is_spawned
        wait_for_socket
      end
      request = Net::HTTP::Post.new("/#{method}")
      request.body = JSON.dump(args)
      client = Client.new("unix://#{socket_path}")
      response = client.request(request)
      raise Jass::Error if response.is_a?(Net::HTTPClientError) # TODO
      JSON.parse(response.body)
    rescue Errno::EPIPE, IOError
      # TODO(bouk): restart or something? If this happens the process is completely broken
      raise Jass::Error, "Node process failed:\n#{@node_stderr.read}"
    end
    
  end
end
