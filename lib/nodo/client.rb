require 'net/http'

module Nodo
  class Client < Net::HTTP
    UNIX_REGEXP = /\Aunix:\/\//i

    def initialize(address, port = nil)
      super(address, port)
      case address
      when UNIX_REGEXP
        @socket_type = 'unix'
        @socket_path = address.sub(UNIX_REGEXP, '')
        # Host header is required for HTTP/1.1
        @address = 'localhost'
        @port = 80
      else
        @socket_type = 'inet'
      end
    end

    def connect
      if @socket_type == 'unix'
        connect_unix
      else
        super
      end
    end

    def connect_unix
      s = Timeout.timeout(@open_timeout) { UNIXSocket.open(@socket_path) }
      @socket = Net::BufferedIO.new(s, read_timeout: @read_timeout,
                                       write_timeout: @write_timeout,
                                       continue_timeout: @continue_timeout,
                                       debug_output: @debug_output)
      on_connect
    end
  end
end
