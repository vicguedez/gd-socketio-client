extends Node
class_name EngineIoTransport

# https://www.rfc-editor.org/rfc/rfc6455#section-7.4
enum CloseStatusCode {
	NORMAL = 1000,
	GONE = 1001,
	PROTOCOL_ERROR = 1002,
	}

class Options:
	# The host for our connection, it should not include port, path or query.
	# e.g ws://localhost, wss://localhost
	var host: String = 'ws://localhost'
	# The port for our connection.
	var port: int = 0
	# The path for our connection.
	var path: String = '/engine.io'
	# Any query parameters in our uri.
	var query: Dictionary = {}
	# Array of protocol strings. These strings are used to indicate 
	# sub-protocols, so that a single server can implement multiple WebSocket 
	# sub-protocols (for example, you might want one server to be able to 
	# handle different types of interactions depending on the specified 
	# protocol)
	var protocols: Array = []
	
	func _to_string() -> String:
		return var_to_str({
			'host': host,
			'port': port,
			'path': path,
			'query': query,
			'protocols': protocols
		})
	
	func duplicate() -> Options:
		return Options.new().parse(str_to_var('%s' % self))
	
	func parse(dict: Dictionary) -> Options:
		host = dict.get('host', host)
		port = dict.get('port', port)
		path = dict.get('path', path)
		query = dict.get('query', query)
		protocols = dict.get('protocols', protocols)
		
		return self
	
	func uri() -> String:
		var _schema = 'wss' if host.begins_with('wss://') else 'ws'
		var _port = ''
		
		if (_schema == 'wss' and port > 0 and port != 443) or \
				(_schema == 'ws' and port > 0 and port != 80):
			
			_port = ':%s' % port
		
		var _query = query.duplicate(true)
		
		_query['EIO'] = EngineIoParser.PROTOCOL
		_query['transport'] = 'websocket'
		
		var _http = HTTPClient.new()
		var _encodedQuery = _http.query_string_from_dict(_query)
		
		var uri = '%s%s%s%s' % [
			host,
			_port,
			path,
			('?%s' % _encodedQuery) if not _encodedQuery.is_empty() else ''
		]
		
		return uri

class Websocket:
	signal open
	signal packet
	signal drain
	signal error
	signal close
	
	enum State {
		CLOSED,
		OPENING,
		OPEN,
		}
	
	var _encode: EngineIoParser.Encoder = EngineIoParser.Encoder.new()
	var _decode: EngineIoParser.Decoder = EngineIoParser.Decoder.new()
	var _state: State = State.CLOSED
	var _writable: bool = false
	var _options: Options
	var _wsp: WebSocketPeer
	
	func _init(options: Options) -> void:
		_options = options
	
	func _open() -> void:
		_wsp = WebSocketPeer.new()
		_wsp.supported_protocols = _options.protocols
		
		var result = _wsp.connect_to_url(_options.uri())
		
		if result != OK:
			_on_connection_error('Websocket transport connect attempt error %s' % result)
	
	func _close(code: int, reason: String) -> void:
		_wsp.close(code, reason)
	
	func _drain() -> void:
		_writable = true
		
		drain.emit()
	
	func _send(packet_list: Array) -> void:
		if not _writable:
			push_warning('Websocket transport sending packets when writable is set to false')
		
		_writable = false
		
		for packet: EngineIoParser.Packet in packet_list:
			_wsp.send(
					_encode.as_string(packet).to_utf8_buffer(),
					WebSocketPeer.WRITE_MODE_TEXT
				)
		
		_drain.call_deferred()
	
	func _on_connection_error(_error: String) -> void:
		error.emit(_error)
	
	func _on_connection_opened() -> void:
		_state = State.OPEN
		_writable = true
		
		open.emit()
	
	func _on_connection_closed(code: int, reason: String) -> void:
		_state = State.CLOSED
		_writable = false
		
		close.emit(code, reason)
	
	func _on_connection_data(data: String) -> void:
		var _packet = _decode.from_string(data)
		
		_on_connection_packet(_packet)
	
	func _on_connection_packet(_packet: EngineIoParser.Packet) -> void:
		packet.emit(_packet)
	
	func do_open() -> void:
		if _state != State.CLOSED:
			push_warning('Websocket transport state is not CLOSED, ignoring OPEN request.')
			return
		
		_state = State.OPENING
		
		_open()
	
	func do_close(code: int, reason: String) -> void:
		if _state == State.CLOSED:
			push_warning('Websocket transport state is CLOSED, ignoring CLOSE request.')
			return
		
		_close(code, reason)
	
	func send(packet_list: Array) -> void:
		if _state != State.OPEN:
			push_warning('Websocket transport state is not OPEN, ignoring SEND request')
			return
		
		_send(packet_list)
	
	func poll() -> void:
		if not is_instance_valid(_wsp) or _state == State.CLOSED:
			return
		
		_wsp.poll()
		
		var state = _wsp.get_ready_state()
		
		if state == WebSocketPeer.STATE_OPEN:
			if _state == State.OPENING:
				_on_connection_opened()
			
			while _wsp.get_available_packet_count():
				_on_connection_data(
						_wsp.get_packet().get_string_from_utf8()
					)
		elif state == WebSocketPeer.STATE_CLOSED:
			if _state == State.OPENING:
				_on_connection_closed(
						-1,
						'Websocket transport could not connect to host'
					)
			else:
				_on_connection_closed(
						_wsp.get_close_code(),
						_wsp.get_close_reason()
					)
	
	func disconnect_all_signals() -> void:
		var signal_list = get_signal_list()
		
		for signal_data in signal_list:
			var signal_connections = get_signal_connection_list(signal_data.name)
			
			for connection in signal_connections:
				self.disconnect(signal_data.name, connection.callable)
