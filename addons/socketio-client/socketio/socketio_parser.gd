extends RefCounted
class_name SocketIoParser

const PROTOCOL = 5

enum PacketType {
	ERROR = -1,
	CONNECT,
	DISCONNECT,
	EVENT,
	ACK,
	CONNECT_ERROR,
	BINARY_EVENT,
	BINARY_ACK
	}

class Packet:
	var error: String
	
	var type: int
	var name_space: String
	var data
	
	func parse(dict: Dictionary) -> Packet:
		type = dict.get('type', type)
		name_space = dict.get('namespace', name_space)
		data = dict.get('data', data)
		
		return self
	
	func _to_string() -> String:
		return var_to_str({
			'error': error,
			'type': type,
			'namespace': name_space,
			'data': data
		})

class Encoder:
	var _debug: bool
	
	func _init(debug = false) -> void:
		_debug = debug
	
	func as_string(packet: Packet) -> String:
		if _debug:
			print('Encoding packet as string: %s' % packet)
		
		# Start with packet type
		var string = '%s' % packet.type
		
		# Add name_space if not root
		if not packet.name_space.is_empty() and packet.name_space != '/':
			string += '%s,' % packet.name_space
		
		# Data as json
		if packet.data and not packet.data.is_empty():
			string += '%s' % JSON.stringify(packet.data)
		
		if _debug:
			print('Packet encoded as: ' + string)
		
		return string

class Decoder:
	var _debug: bool
	
	func _init(debug = false) -> void:
		_debug = debug
	
	func _payload_is_valid(type: int, payload) -> bool:
		var valid: bool = false
		
		match type:
			PacketType.CONNECT:
				valid = typeof(payload) == TYPE_DICTIONARY
			PacketType.DISCONNECT:
				valid = typeof(payload) == TYPE_NIL
			PacketType.EVENT:
				valid = typeof(payload) == TYPE_ARRAY and (payload as Array).size() > 0
			PacketType.ACK:
				valid = typeof(payload) == TYPE_ARRAY
			PacketType.CONNECT_ERROR:
				valid = typeof(payload) == TYPE_STRING or typeof(payload) == TYPE_DICTIONARY
		
		return valid
	
	func from_string(packet_string: String) -> Packet:
		if _debug:
			print('Decoding string as packet: ' + packet_string)
		
		var packet = Packet.new()
		var type = int(packet_string[0])
		
		if not type in PacketType.values() or \
				type == PacketType.ACK or \
				type == PacketType.BINARY_EVENT or \
				type == PacketType.BINARY_ACK:
			
			packet.type = PacketType.ERROR
			packet.error = 'Decoded packet type not supported: %s' % type
			
			if _debug:
				push_error(packet.error)
			
			return packet
		
		packet_string = packet_string.substr(1)
		
		var name_space = '/'
		
		if packet_string.length() and packet_string[0] == name_space:
			var separator_at = packet_string.find(',')
			
			name_space = packet_string.left(separator_at)
			# Increase index by 1 to get rid of the comma.
			packet_string = packet_string.substr(separator_at + 1)
		
		var id: String
		
		while packet_string.length():
			var character: String = packet_string[0]
			
			if not character.is_valid_int():
				break
			
			id += character
			
			packet_string = packet_string.substr(1)
		
		var data
		
		if packet_string.length():
			var payload = str_to_var(packet_string)
			var valid_payload = _payload_is_valid(type, payload)
			
			if not valid_payload:
				packet.type = PacketType.ERROR
				packet.error = 'Decoded packet payload not valid: %s' % packet_string
				
				if _debug:
					push_error(packet.error)
				
				return packet
			
			data = payload
		
		packet.type = type
		packet.name_space = name_space
		
		if id:
			packet.id = int(id)
		
		if data:
			packet.data = data
		
		if _debug:
			print('String decoded as packet: %s' % packet)
		
		return packet
