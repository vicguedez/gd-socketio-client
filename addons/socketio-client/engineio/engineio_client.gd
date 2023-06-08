extends RefCounted
class_name EngineIoClient

class Socket:
	signal open
	signal handshake
	signal packet
	signal packet_create
	signal data
	signal drain
	signal flush
	signal heartbeat
	signal ping
	signal pong
	signal error
	signal close
	
	enum State {
		CLOSED,
		OPENING,
		OPEN,
		CLOSING,
		}
	
	var _sid: String
	var _transport: EngineIoTransport.Websocket
	var _state: int
	var _write_buffer: Array
	var _prev_write_buffer_size: int
	var _ping_interval: int
	var _ping_timeout: int
	var _ping_last_msec: int = 0
	var _options: EngineIoTransport.Options
	
	func _init(options: EngineIoTransport.Options) -> void:
		_options = options
	
	func _on_open() -> void:
		_state = State.OPEN
		
		open.emit()
		
		_reset_ping_timer()
		
		do_flush()
	
	func _send_packet(type: int, data = null) -> void:
		var packet = EngineIoParser.Packet.new().parse({
			'type': type
		})
		
		if data:
			packet.data = data
		
		packet_create.emit(packet)
		
		_write_buffer.append(packet)
		
		do_flush()
	
	func _check_ping_timeout() -> void:
		var msec_since_last_ping = Time.get_ticks_msec() - _ping_last_msec
		
		if msec_since_last_ping < _ping_timeout:
			return
		
		_transport.do_close(EngineIoTransport.CloseStatusCode.GONE, 'Ping timeout reached')
	
	func _reset_ping_timer() -> void:
		_ping_last_msec = Time.get_ticks_msec()
	
	func _on_handshake_packet(packet: EngineIoParser.Packet) -> void:
		var data: Dictionary = str_to_var(packet.data)
		
		handshake.emit(data)
		
		_transport._options.query['sid'] = data.sid
		
		_sid = data.sid
		_ping_interval = data.pingInterval
		_ping_timeout = data.pingTimeout
		
		_on_open()
	
	func _on_ping_packet() -> void:
		_reset_ping_timer()
		_send_packet(EngineIoParser.PacketType.PONG)
		
		ping.emit()
		pong.emit()
	
	func _on_error_packet(packet: EngineIoParser.Packet) -> void:
		error.emit(packet.error)
		
		_transport.do_close(EngineIoTransport.CloseStatusCode.PROTOCOL_ERROR, 'Recevied packet with error')
	
	func _on_message_packet(packet: EngineIoParser.Packet) -> void:
		data.emit(packet.data)
	
	func _on_transport_error(reason: String) -> void:
		_on_transport_close(-1, reason)
	
	func _on_transport_packet(new_packet: EngineIoParser.Packet) -> void:
		if _state == State.CLOSED:
			return
		
		packet.emit(new_packet)
		heartbeat.emit()
		
		match new_packet.type:
			EngineIoParser.PacketType.OPEN:
				_on_handshake_packet(new_packet)
			EngineIoParser.PacketType.PING:
				_on_ping_packet()
			EngineIoParser.PacketType.ERROR:
				_on_error_packet(new_packet)
			EngineIoParser.PacketType.MESSAGE:
				_on_message_packet(new_packet)
	
	func _on_transport_drain() -> void:
		if _prev_write_buffer_size == _write_buffer.size():
			_write_buffer.clear()
		else:
			_write_buffer = _write_buffer.slice(0, _prev_write_buffer_size - 1)
		
		_prev_write_buffer_size = 0
		
		if _write_buffer.size():
			do_flush()
		else:
			drain.emit()
	
	func _on_transport_close(code: int, reason: String) -> void:
		_sid = ''
		_state = State.CLOSED
		_write_buffer = []
		_prev_write_buffer_size = 0
		_transport.disconnect_all_signals()
		
		close.emit(code, reason)
	
	func do_open() -> void:
		if _state != State.CLOSED:
			return
		
		_state = State.OPENING
		
		var options := _options.duplicate()
		
		if not _sid.is_empty():
			options.query['sid'] = _sid
		
		_transport = EngineIoTransport.Websocket.new(options)
		_transport.error.connect(_on_transport_error)
		_transport.packet.connect(_on_transport_packet)
		_transport.drain.connect(_on_transport_drain)
		_transport.close.connect(_on_transport_close)
		_transport.do_open()
	
	func do_close(code: int, reason: String) -> void:
		if _state != State.OPENING and _state != State.OPEN:
			return
		
		_state = State.CLOSING
		
		if _write_buffer.size():
			await self.drain
		
		_transport.do_close(code, reason)
	
	func do_flush() -> void:
		if _state == State.CLOSED or \
				not _transport._writable or \
				not _write_buffer.size():
			
			return
		
		_transport.send(_write_buffer)
		_prev_write_buffer_size = _write_buffer.size()
		
		flush.emit()
	
	func poll() -> void:
		if not is_instance_valid(_transport):
			return
		
		if _state == State.OPEN:
			_check_ping_timeout()
		
		_transport.poll()
	
	func write(data: String) -> void:
		_send_packet(EngineIoParser.PacketType.MESSAGE, data)
	
	func disconnect_all_signals() -> void:
		var signal_list = get_signal_list()
		
		for signal_data in signal_list:
			var signal_connections = get_signal_connection_list(signal_data.name)
			
			for connection in signal_connections:
				self.disconnect(signal_data.name, connection.callable)
