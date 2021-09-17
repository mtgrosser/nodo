require 'set'
require 'pathname'
require 'open3'
require 'json'
require 'fileutils'
require 'tmpdir'

require_relative 'core/version'
require_relative 'errors'
require_relative 'core/client'
require_relative 'dependency'
require_relative 'function'
require_relative 'constant'

module Jass
  class << self
    attr_accessor :modules_root
  end
  
  class Core
    attr_reader :root, :env, :tmpdir
    
    class << self
      %i[dependencies functions constants].each do |attr|
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

      def generate_code
        <<~JS
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
          function __jass_render_exception(e) {
            let errInfo = {};
            if (e instanceof Error) {
              errInfo.name = e.name;
              Object.getOwnPropertyNames(e).reduce((obj, prop) => { obj[prop] = e[prop]; return obj }, errInfo);
            } else {
              errInfo.name = e.toString();
            }
            return JSON.stringify({ error: errInfo });
          }

          function __jass_render_error(error) {
            let errInfo = { name: error || 'RUNTIME_ERROR' }
            return JSON.stringify({ error: errInfo });
          }

          function __jass_respond_with_error(res, code, name) {
            res.statusCode = code;
            __jass_log.log(`Error ${code} ${name}`);
            res.end(__jass_render_error(name));
          }
          
          function __jass_log(message) {
            //appendFileSync('jass.log', `${message}\\n`);
          }
          
          const http = require('http');
          const path = require('path');
          const fs = require('fs');
          
          const tmpdir = process.argv[1];
          const socket = path.join(tmpdir, 'jass.sock');
          
          try {
            #{dependencies.map(&:to_js).join}
          } catch (e) {
            // STDIN __jass_handle_error(e);
            process.stderr.write(e.toString());
            process.stderr.write(`\\n`);
            process.exit(1);
          }
          
          process.stdout.write('Starting up... ');
          // process.stdout.write("[\\"ok\\"]\\n");
          
          #{constants.map(&:to_js).join}
          
          const __jass_methods = {};
          #{functions.map(&:to_js).join}
          
/*          require('readline').createInterface({
            input: process.stdin,
            terminal: false,
          }).on('line', function(line) {
            var input = JSON.parse(line);
            try {
              let result = __jass_methods[input[0]].apply(null, input[1]);
              process.stdout.write(`${JSON.stringify(['ok', result])}\\n`);
            } catch(error) {
              __jass_handle_error(error);
            }
          });
*/          
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
                result = __jass_methods[method].apply(null, input);
              } catch(error) {
                return __jass_respond_with_error(res, 500, 'Internal Server Error');
              }
    
              res.statusCode = 200;
              res.end(JSON.stringify(result));
              console.log(`Completed 200 OK`);
            });
          });

          server.listen(socket, () => {
            process.stdout.write(`server ready, listening on ${socket}\\n`);
          });

          let closing;

          const shutdown = () => {
            process.stdout.write("Shutting down\\n");
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
          FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir)
          stdin, stdout, stderr, process_thread = process_data
          stdin.close
          stdout.close
          stderr.close
          Process.kill(0, process_thread.pid)
          process_thread.value
        end
      end
    end

    def initialize(root = Jass.modules_root, env = {})
      @root = root || '.'
      @env = env || {}
      @env['NODE_PATH'] ||= root.to_s
    end

    def pid
      @node_process_thread && @node_process_thread.pid
    end

    private
    
    def ensure_process_is_spawned
      return if @node_process_thread
      spawn_process
    end

    def spawn_process
      @tmpdir = Pathname.new(Dir.mktmpdir('jass'))
      process_data = Open3.popen3(env, 'node', '-e', self.class.generate_code, '--', @tmpdir.to_s)
      @node_stdin, @node_stdout, @node_stderr, @node_process_thread = process_data
      ensure_packages_are_initiated(*process_data)
      ObjectSpace.define_finalizer(self, self.class.send(:finalize, process_data, @tmpdir))
    end
=begin
    def ensure_packages_are_initiated(stdin, stdout, stderr, process_thread)
      input = stdout.gets
      raise Jass::Error, "Failed to instantiate Node process:\n#{stderr.read}" if input.nil?
      result = JSON.parse(input)
      unless result[0] == 'ok'
        stdin.close
        stdout.close
        stderr.close
        process_thread.join

        error = result[1]
        if error.is_a?(Hash)
          raise Jass::DependencyError.new(error)
        elsif error.is_a?(String)
          raise Jass::Error, error
        end
      end
    end
=end
    def ensure_packages_are_initiated(stdin, stdout, stderr, process_thread)
      input = stdout.gets
      raise Jass::Error, "Failed to instantiate Node process:\n#{stderr.read}" if input.nil?
      #unless input.include?('server ready')
      #  stdout.close
      #  stderr.close
      #  process_thread.join
      #  raise Jass::Error
      #end
    end
=begin    
    def call_js_method(method, args)
      ensure_process_is_spawned

      @node_stdin.puts JSON.dump([method, args])
      input = @node_stdout.gets
      raise Errno::EPIPE, "Can't read from stdout" if input.nil?
      status, result = JSON.parse(input)
      return result if status == 'ok'
      raise Jass::JavaScriptError.new(result)
    rescue Errno::EPIPE, IOError
      raise Jass::Error, "Node process failed:\n#{@node_stderr.read}"
    end
=end
    def call_js_method(method, args)
      ensure_process_is_spawned
      request = Net::HTTP::Post.new("/#{method}")
      request.body = JSON.dump(args)
      client = Client.new("unix://#{tmpdir.join('jass.sock')}")
      response = client.request(request)
    
      if response.is_a?(Net::HTTPClientError)
        raise Jass::Error
      else
        result = JSON.parse(response.body)
        return result
      end
    rescue Errno::EPIPE, IOError
      # TODO(bouk): restart or something? If this happens the process is completely broken
      raise Jass::Error, "Node process failed:\n#{@node_stderr.read}"
    end
    
  end
end
