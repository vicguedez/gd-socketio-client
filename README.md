# gd-socketio-client
A basic, naively written unofficial GDScript client for SocketIO v4 and Godot 4.

# Installing
Copy `addons/socketio-client` into your project, and thats it. Godot addons usually require enabling/disabling but it is not needed in this case.

# Addon test
You can find a basic test scene already setup in `_gd_socketio_client_test/` folder.

# Before using
This addon API is modelled after https://github.com/socketio/socket.io-client. But, **this is not a complete or production ready port**, be warned:

- This only supports text messages, so no binary.
- This only supports the "websocket" transport.
- Acknowledgements are not supported (I might implement them in the future).
- Message compression/deflate is not supported / tested.

# Using
To start using SocketIo client, all you need is this:

```gdscript
const OPTIONS: Dictionary = {
  'host': 'ws://localhost',
  'port': 8080,
  }

var manager_options: SocketIoClient.ManagerOptions
var manager: SocketIoClient.Manager
var socket: SocketIoClient.Socket

func _ready() -> void:
  manager_options = SocketIoClient.ManagerOptions.new(OPTIONS)
  manager = SocketIoClient.Manager.new(manager_options)
  socket = manager.socket()
  
  socket.connected.connect(on_socket_connected)
  socket.connection_error.connect(on_socket_connection_error)
  socket.disconnected.connect(on_socket_disconnected)
  socket.disconnecting.connect(on_socket_disconnecting)
  
  socket.once("my-custom-event", my_custom_event_once)
```

You will of course have to implement the missing funcs to your liking, but thats all you need for a basic connection.

# API

Methods, options and signals not listed here are not meant for regular use, use those only if you know what you are doing. 

### SocketIoClient.SocketOptions
#### Default options
```gdscript
{
  "auth": {}
}
```

### SocketIoClient.Socket
#### Signals
```gdscript
signal connected
signal connection_error
signal disconnected
signal disconnecting
```

#### Methods
```gdscript
func open() -> Socket
func close() -> Socket
func emit(event: String, args: Array = []) -> Socket:
func on(event: String, callback: Callable) -> void:
func once(event: String, callback: Callable) -> void:
func off(event: String, callback: Callable) -> void:
func offAny(event: String) -> void:
func offAll() -> void:
func volatile() -> Socket:
```

### SocketIoClient.ManagerOptions
#### Default options
```gdscript
{
  "auto_connect": true,
  "host": "ws://localhost",
  "path": "/socket.io/",
  "port": 0,
  "protocols": [],
  "query": {},
  "reconnection": true,
  "reconnection_attempts": INF,
  "reconnection_delay": 1.0,
  "reconnection_delay_max": 5.0
}
```

### SocketIoClient.Manager
#### Signals
```gdscript
# Use Socket's signals over these unless you know what you are doing.
signal open
signal error
signal ping
signal packet
signal close
signal reconnect_failed
signal reconnect_attempt
signal reconnect_error
signal reconnect
```

#### Methods
```gdscript
# Use this method to get a new connection to the host.
func socket(name_space = "/", options: SocketOptions = SocketOptions.new()) -> Socket
```
