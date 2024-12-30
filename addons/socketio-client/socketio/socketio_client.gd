extends RefCounted
class_name SocketIoClient

const EVENT_ARGS_MISMATCH_ERR = "Cannot call event %s on %s:%s, method argument count is %s but event has %s."

class ManagerOptions:
	var host: String = 'ws://localhost'
	var port: int = 0
	var path: String = '/socket.io/'
	var query: Dictionary = {}
	var protocols: Array = []
	var reconnection: bool = true
	var reconnection_attempts: int = INF
	# Note seconds
	var reconnection_delay: float = 1.0
	# Note seconds
	var reconnection_delay_max: float = 5.0
	var auto_connect: bool = true
	
	func _init(dict: Dictionary = {}) -> void:
		parse(dict)
	
	func _to_string() -> String:
		return var_to_str(to_dict())
	
	func to_dict() -> Dictionary:
		return {
			'host': host,
			'port': port,
			'path': path,
			'query': query,
			'protocols': protocols,
			'reconnection': reconnection,
			'reconnection_attempts': reconnection_attempts,
			'reconnection_delay': reconnection_delay,
			'reconnection_delay_max': reconnection_delay_max,
			'auto_connect': auto_connect
		}
	
	func duplicate() -> ManagerOptions:
		return ManagerOptions.new().parse(to_dict())
	
	func parse(dict: Dictionary) -> ManagerOptions:
		host = dict.get('host', host)
		port = dict.get('port', port)
		path = dict.get('path', path)
		query = dict.get('query', query)
		protocols = dict.get('protocols', protocols)
		reconnection = dict.get('reconnection', reconnection)
		reconnection_attempts = dict.get('reconnection_attempts', reconnection_attempts)
		reconnection_delay = dict.get('reconnection_delay', reconnection_delay)
		reconnection_delay_max = dict.get('reconnection_delay_max', reconnection_delay_max)
		auto_connect = dict.get('auto_connect', auto_connect)
		
		return self

class Manager:
	signal open
	signal error
	signal ping
	signal packet
	signal close
	signal reconnect_failed
	signal reconnect_attempt
	signal reconnect_error
	signal reconnect
	
	enum State {
		CLOSED,
		OPENING,
		OPEN,
		RECONNECTING,
		}
	
	var _state: int = State.CLOSED
	var _engine: EngineIoClient.Socket
	var _options: ManagerOptions
	var _reconnection_skip: bool = false
	var _reconnection_attempts: int = 0
	var _reconnection_delay: float = 0.0
	var _reconnection_last_attempt_at: int = 0
	var _namespace_sockets: Dictionary = {}
	var _encode: SocketIoParser.Encoder = SocketIoParser.Encoder.new()
	var _decode: SocketIoParser.Decoder = SocketIoParser.Decoder.new()
	
	func _init(options := ManagerOptions.new()) -> void:
		_options = options
		_reconnection_delay = min(options.reconnection_delay, options.reconnection_delay_max)
		
		if options.auto_connect:
			do_open()
	
	func _on_engine_open() -> void:
		var prev_state = _state
		
		_state = State.OPEN
		_reconnection_skip = false
		_reconnection_attempts = 0
		_reconnection_delay = min(_options.reconnection_delay, _options.reconnection_delay_max)
		
		if prev_state == State.RECONNECTING:
			reconnect.emit(_reconnection_attempts)
		else:
			open.emit()
	
	func _on_engine_error(engine_error: String) -> void:
		if _state != State.RECONNECTING:
			error.emit(engine_error)
		else:
			_reconnect_engine()
			
			reconnect_error.emit(engine_error)
	
	func _on_engine_ping() -> void:
		ping.emit()
	
	func _on_engine_data(data: String) -> void:
		var new_packet = _decode.from_string(data)
		
		if new_packet.type == SocketIoParser.PacketType.ERROR:
			_engine.do_close(
					EngineIoTransport.CloseStatusCode.PROTOCOL_ERROR,
					new_packet.error
				)
			
			return
		
		packet.emit(new_packet)
	
	func _on_engine_close(code: int, reason: String) -> void:
		close.emit(code, reason)
		
		if _options.reconnection and not _reconnection_skip:
			_state = State.RECONNECTING
			_reconnect_engine()
		else:
			_state = State.CLOSED
	
	func _reconnect_engine() -> void:
		if _reconnection_attempts >= _options.reconnection_attempts:
			_state = State.CLOSED
			reconnect_failed.emit()
			
			return
		
		_reconnection_last_attempt_at = Time.get_ticks_msec()
	
	func _attempt_reconnection() -> void:
		var msec_since_last_attempt = Time.get_ticks_msec() - _reconnection_last_attempt_at
		var secs_since_last_attempt = msec_since_last_attempt / 1000.0
		
		if secs_since_last_attempt < _reconnection_delay:
			return
		
		_reconnection_attempts += 1
		_reconnection_delay = min(
				_reconnection_delay + _options.reconnection_delay,
				_options.reconnection_delay_max
			)
		
		if _reconnection_skip:
			return
		
		reconnect_attempt.emit(_reconnection_attempts)
		
		if _reconnection_skip:
			return
		
		_engine.do_open()
	
	func _write(packet: SocketIoParser.Packet) -> void:
		var encoded = _encode.as_string(packet)
		
		_engine.write(encoded)
	
	func reconnection_attempts_left() -> int:
		if _options.reconnection_attempts == INF:
			return INF
		
		return _options.reconnection_attempts - _reconnection_attempts
	
	func do_open() -> void:
		if _state != State.CLOSED:
			return
		
		var options_dict = _options.to_dict()
		var engine_options = EngineIoTransport.Options.new().parse(options_dict)
		
		_engine = EngineIoClient.Socket.new(engine_options)
		_state = State.OPENING
		_reconnection_last_attempt_at = Time.get_ticks_msec()
		
		_engine.open.connect(_on_engine_open)
		_engine.error.connect(_on_engine_error)
		_engine.ping.connect(_on_engine_ping)
		_engine.data.connect(_on_engine_data)
		_engine.close.connect(_on_engine_close)
		_engine.do_open()
	
	func do_close(code: int, reason: String = '') -> void:
		if _state == State.CLOSED:
			return
		
		_reconnection_skip = true
		_engine.do_close(code, reason)
	
	func socket(name_space: String = '/', options: SocketOptions = SocketOptions.new()) -> Socket:
		var socket = _namespace_sockets.get(name_space) as Socket
		
		if socket == null:
			socket = Socket.new(self, name_space, options)
			
			_namespace_sockets[name_space] = socket
		
		return socket
	
	func destroy(socket: Socket) -> void:
		var list = _namespace_sockets.keys()
		
		for name_space in list:
			var _socket: Socket = _namespace_sockets[name_space]
			
			if _socket.active:
				return
		
		do_close(EngineIoTransport.CloseStatusCode.NORMAL)
	
	func poll() -> void:
		if not is_instance_valid(_engine):
			return
		
		if _state == State.RECONNECTING:
			_attempt_reconnection()
		
		_engine.poll()

class SocketOptions:
	var auth: Dictionary
	
	func _to_string() -> String:
		return var_to_str(to_dict())
	
	func to_dict() -> Dictionary:
		return {
			'auth': auth,
		}
	
	func duplicate() -> SocketOptions:
		return SocketOptions.new().parse(to_dict())
	
	func parse(dict: Dictionary) -> SocketOptions:
		auth = dict.get('auth', auth)
		
		return self

class Socket:
	signal connected
	signal connection_error
	signal disconnected
	signal disconnecting
	
	const FLAG_VOLATILE = "volatile"
	const RESERVED_EVENTS = [
		'connect',
		'connect_error',
		'disconnect',
		'disconnecting',
		]
	
	var _receive_buffer := []
	var _send_buffer := []
	var _manager: Manager
	var _namespace: String
	var _acknowledgement_id := 0
	var _acknowledgements: Dictionary
	var _flags: Dictionary
	var _listeners: Dictionary
	var _listeners_id: int = 0
	
	var sid: String
	var is_connected: bool
	var active: bool:
		set(_value):
			pass
		get:
			return _get_active()
	var auth: Dictionary
	
	func _init(manager: Manager, name_space: String, options: SocketOptions) -> void:
		_manager = manager
		_namespace = name_space
		
		auth = options.auth
		
		if _manager._options.auto_connect:
			open()
	
	func _get_active() -> bool:
		return (
				_manager.open.is_connected(_on_manager_open)
				if is_instance_valid(_manager)
				else false
			)
	
	func _on_connected(_sid: String) -> void:
		sid = _sid
		is_connected = true
		
		_process_buffered()
		
		connected.emit()
	
	func _on_event(packet: SocketIoParser.Packet) -> void:
		if not is_connected:
			_receive_buffer.append(packet)
			
			return
		
		_emit_event(packet)
	
	func _on_disconnected() -> void:
		_destroy()
		_on_manager_close(EngineIoTransport.CloseStatusCode.GONE, 'io server disconnect')
	
	func _on_manager_open() -> void:
		var packet = SocketIoParser.Packet.new().parse({
			'type': SocketIoParser.PacketType.CONNECT,
			'data': auth
		})
		
		_write(packet)
	
	func _on_manager_packet(packet: SocketIoParser.Packet) -> void:
		if not packet.name_space == _namespace:
			return
		
		match packet.type:
			SocketIoParser.PacketType.CONNECT:
				var _sid: String
				
				if typeof(packet.data) == TYPE_DICTIONARY:
					_sid = packet.data.get('sid', '')
				
				if _sid.is_empty():
					connection_error.emit('It seems you are trying to reach a Socket.IO server in v2.x with a v3.x client, but they are not compatible (more information here: https://socket.io/docs/v3/migrating-from-2-x-to-3-0/)')
				else:
					_on_connected(_sid)
			SocketIoParser.PacketType.EVENT:
				_on_event(packet)
			SocketIoParser.PacketType.DISCONNECT:
				_on_disconnected()
			SocketIoParser.PacketType.CONNECT_ERROR:
				_destroy()
				
				connection_error.emit(packet.data.message)
	
	func _on_manager_error(error: String) -> void:
		if not is_connected:
			connection_error.emit(error)
	
	func _on_manager_close(code: int, reason: String) -> void:
		is_connected = false
		sid = ''
		
		disconnected.emit(code, reason)
	
	func _write(packet: SocketIoParser.Packet) -> void:
		packet.name_space = _namespace
		
		_manager._write(packet)
	
	func _process_buffered() -> void:
		for packet in _receive_buffer:
			_emit_event(packet)
		
		_receive_buffer = []
		
		for packet in _send_buffer:
			_write(packet)
		
		_send_buffer = []
	
	func _emit_event(packet: SocketIoParser.Packet) -> void:
		var event: String = packet.data.pop_front()
		var to_remove = []
		
		for listener_id in _listeners.get(event, {}):
			var listener: Array = _listeners[event][listener_id]
			var callback: Callable = listener[0]
			var one_shot: bool = listener[1]
			
			if not callback.is_valid():
				to_remove.append(listener_id)
				
				continue
			
			if callback.get_argument_count() != packet.data.size():
				push_error(EVENT_ARGS_MISMATCH_ERR % [
					event,
					callback.get_object(),
					callback.get_method(),
					callback.get_argument_count(),
					packet.data.size(),
				])
			else:
				callback.callv(packet.data)
			
			if one_shot:
				to_remove.append(listener_id)
		
		for id in to_remove:
			_listeners.get(event, {}).erase(id)
	
	func _destroy() -> void:
		_manager.open.disconnect(_on_manager_open)
		_manager.packet.disconnect(_on_manager_packet)
		_manager.error.disconnect(_on_manager_error)
		_manager.close.disconnect(_on_manager_close)
		_manager.destroy(self)
	
	func open() -> Socket:
		if is_connected:
			return self
		
		_manager.open.connect(_on_manager_open)
		_manager.packet.connect(_on_manager_packet)
		_manager.error.connect(_on_manager_error)
		_manager.close.connect(_on_manager_close)
		
		if _manager._state != Manager.State.RECONNECTING:
			_manager.do_open()
		if _manager._state == Manager.State.OPEN:
			_on_manager_open()
		
		return self
	
	func close() -> Socket:
		if is_connected:
			var packet = SocketIoParser.Packet.new().parse({
				'type': SocketIoParser.PacketType.DISCONNECT
			})
			
			_write(packet)
		
		_destroy()
		
		if is_connected:
			_on_manager_close(EngineIoTransport.CloseStatusCode.NORMAL, 'io client disconnect')
		
		return self
	
	func emit(event: String, args: Array = []) -> Socket:
		if RESERVED_EVENTS.has(event):
			push_error('%s is a reserved event' % event)
			
			return self
		
		args.push_front(event)
		
		var packet = SocketIoParser.Packet.new()
		
		packet.type = SocketIoParser.PacketType.EVENT
		packet.data = args
		
		var transport_writable = (
				_manager._engine != null
				and _manager._engine._transport != null
				and _manager._engine._transport._writable
			)
		
		var discard_packet = (
				_flags.get(FLAG_VOLATILE, false)
				and (not transport_writable or not is_connected)
			)
		
		if discard_packet:
			push_warning('Discarding packet as the transport is not currently writable')
		elif is_connected:
			_write(packet)
		else:
			_send_buffer.append(packet)
		
		_flags = {}
		
		return self
	
	func on(event: String, callback: Callable) -> void:
		if not _listeners.has(event):
			_listeners[event] = {}
		
		_listeners[event][_listeners_id] = [callback, false]
		_listeners_id += 1
	
	func once(event: String, callback: Callable) -> void:
		if not _listeners.has(event):
			_listeners[event] = {}
		
		_listeners[event][_listeners_id] = [callback, true]
		_listeners_id += 1
	
	func off(event: String, callback: Callable) -> void:
		var to_remove = []
		
		for id in _listeners.get(event, {}):
			var listener = _listeners[event][id]
			var _callback: Callable = listener[0]
			
			if callback != _callback:
				continue
			
			to_remove.append(id)
		
		for id in to_remove:
			_listeners[event].erase(id)
	
	func offAny(event: String) -> void:
		_listeners[event] = {}
	
	func offAll() -> void:
		_listeners = {}
	
	func volatile() -> Socket:
		_flags[FLAG_VOLATILE] = true
		
		return self
