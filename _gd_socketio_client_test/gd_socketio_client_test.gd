extends Control

const OPTIONS: Dictionary = {
	'host': 'ws://localhost',
	'port': 8080,
	'path': '/socket.io/',
	'auto_connect': false,
	'reconnection': false,
	}

var manager_options: SocketIoClient.ManagerOptions
var manager: SocketIoClient.Manager
var socket: SocketIoClient.Socket

func _ready() -> void:
	manager_options = SocketIoClient.ManagerOptions.new(OPTIONS)
	manager = SocketIoClient.Manager.new(manager_options)
	socket = manager.socket()
	
	if OPTIONS.auto_connect:
		_on_connect_pressed()
	else:
		$content/open.pressed.connect(_on_connect_pressed)

func _process(_delta: float) -> void:
	manager.poll()

func _on_connect_pressed() -> void:
	$content/info.text = "Attempting connection, check output for results."
	$content/open.disabled = true
	
	socket.open()
	socket.connected.connect(on_socket_connected)
	socket.connection_error.connect(on_socket_connection_error)
	socket.disconnected.connect(on_socket_disconnected)
	socket.disconnecting.connect(on_socket_disconnecting)
	
	socket.once("my-custom-event", my_custom_event_once)
	
	manager._engine.close.connect(on_close)
	manager._engine.data.connect(on_data)
	manager._engine.drain.connect(on_drain)
	manager._engine.error.connect(on_error)
	manager._engine.flush.connect(on_flush)
	manager._engine.handshake.connect(on_handshake)
	manager._engine.heartbeat.connect(on_heartbeat)
	manager._engine.open.connect(on_open)
	manager._engine.packet.connect(on_packet)
	manager._engine.packet_create.connect(on_packet_create)
	manager._engine.ping.connect(on_ping)
	manager._engine.pong.connect(on_pong)

func my_custom_event_once(foo, bar) -> void:
	printt("My Custom Event Once", foo, bar)

func on_socket_connected() -> void:
	print('Client connected.')

func on_socket_connection_error(reason: String) -> void:
	print('Client connect error. Reason: %s' % reason)

func on_socket_disconnected(code: int, reason: String) -> void:
	print('Client disconnect. Code %s; Reason: %s' % [code, reason])

func on_socket_disconnecting() -> void:
	print('Client disconnecting.')

func on_close(code: int, reason: String) -> void:
	printt('EIO Close. Code: %s; Reason: %s' % [code, reason])

func on_data(value) -> void:
	printt('EIO Data.', value)

func on_drain() -> void:
	printt('EIO Drain.')

func on_error(error: String) -> void:
	printt('EIO Error.', error)

func on_flush() -> void:
	printt('EIO Flush.')

func on_handshake(value) -> void:
	printt('EIO Handshake.', value)

func on_heartbeat() -> void:
	printt('EIO Heartbeat.')

func on_open() -> void:
	printt('EIO Open.')

func on_packet(value) -> void:
	printt('EIO Packet.', value)

func on_packet_create(value) -> void:
	printt('EIO Packet Create.', value)

func on_ping() -> void:
	printt('EIO Ping.')

func on_pong() -> void:
	printt('EIO Pong.')
