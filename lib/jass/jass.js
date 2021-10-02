module.exports = (function() {

  function render_error(e) {
    let errInfo = {};
    if (e instanceof Error) {
      errInfo.name = e.name;
      Object.getOwnPropertyNames(e).reduce((obj, prop) => { obj[prop] = e[prop]; return obj }, errInfo);
    } else {
      errInfo.name = e.toString();
    }
    return JSON.stringify({ error: errInfo });
  }

  function respond_with_error(res, code, name) {
    res.statusCode = code;
    const rendered = render_error(name);
    log(`Error ${code} ${rendered}`);
    res.end(rendered, 'utf8');
  }
  
  function respond_with_data(res, data, start) {
    let timing;
    res.statusCode = 200;
    res.end(JSON.stringify(data), 'utf8');
    if (start) {
      timing = ` in ${(performance.now() - start).toFixed(2)}ms`;
    }
    log(`Completed 200 OK${timing}`);
  }

  function log(message) {
    // __jass_fs.appendFileSync('log/jass.log', `${message}\n`);
    // console.log(`[Jass] ${message}`);
  }
  
  const DEFINE_METHOD = '__jass_define_class__';

  const vm = require('vm');
  const http = require('http');
  const path = require('path');
  const fs = require('fs');
  const performance = require('perf_hooks').performance;
  
  let server, closing;
  const classes = {};
  
  const core = {
    run: (socket) => {
      log('Starting up...');
      server = http.createServer((req, res) => {
        const start = performance.now();
        
        res.setHeader('Content-Type', 'application/json');
        log(`${req.method} ${req.url}`);

        if (req.method !== 'POST' || !req.url.startsWith('/')) {
          return respond_with_error(res, 405, 'Method Not Allowed');
        }
        
        const url = req.url.substring(1);
        const [class_name, method] = url.split('/');
        let klass;
        
        if (classes.hasOwnProperty(class_name)) {
          klass = classes[class_name];
          if (!klass.hasOwnProperty(method)) {
            return respond_with_error(res, 404, `Method ${class_name}#${method} not found`);
          }
        } else if (DEFINE_METHOD != method) {
          return respond_with_error(res, 404, `Class ${class_name} not defined`);
        }
        
        let body = '';
        
        req.on('data', (data) => { body += data; });

        req.on('end', () => {
          let input, result;

          try {
            input = JSON.parse(body);
          } catch (e) {
            return respond_with_error(res, 400, 'Bad Request');
          }

          try {
            if (DEFINE_METHOD == method) {
              let new_class = vm.runInThisContext(input, class_name);
              classes[class_name] = new_class;
              respond_with_data(res, class_name, start);
            } else {
              Promise.resolve(klass[method].apply(null, input)).then(function (result) {
                respond_with_data(res, result, start);
              }).catch(function(error) {
                respond_with_error(res, 500, error);
              });
            }
          } catch(error) {
            return respond_with_error(res, 500, error);
          }
    
        });
      });

      //server.maxConnections = 64;
      server.listen(socket, () => {
        log(`server ready, listening on ${socket} (max connections: ${server.maxConnections})`);
      });
    },
    close: (finalizer) => {
      log("Shutting down");
      if (!closing) {
        closing = true;
        server.close(finalizer);
      }
    }
  };
  
  return { core: core, log: log };
})();
