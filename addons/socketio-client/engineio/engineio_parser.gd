extends RefCounted
class_name EngineIoParser

const PROTOCOL = 4
# see https://en.wikipedia.org/wiki/Delimiter#ASCII_delimited_text
const SEPARATOR: String = char(30)

enum PacketType {
	ERROR = -1,
	OPEN,
	CLOSE,
	PING,
	PONG,
	MESSAGE,
	UPGRADE,
	NOOP,
	}

class Packet:
	var error: String
	var type: PacketType = PacketType.ERROR
	var data: String
	
	func parse(dict: Dictionary) -> Packet:
		type = dict.get('type', type)
		data = dict.get('data', data)
		
		return self
	
	func _to_string() -> String:
		return var_to_str({
			'error': error,
			'type': type,
			'data': data
		})

class Encoder:
	var _debug: bool
	
	func _init(debug = false) -> void:
		_debug = debug
	
	func payload(packet_list: Array[Packet]) -> String:
		var encoded = PackedStringArray([])
		
		for packet in packet_list:
			encoded.append(as_string(packet))
		
		return SEPARATOR.join(encoded)
	
	func as_string(packet: Packet) -> String:
		if _debug:
			print('Encoding packet as string: %s' % packet)
		
		var string = '%s' % packet.type
		
		if not packet.data.is_empty():
			string += packet.data
		
		if _debug:
			print('Encoded packet as string: %s' % string)
		
		return string

class Decoder:
	var _debug: bool
	
	func _init(debug = false) -> void:
		_debug = debug
	
	func payload(payload_string: String) -> Array:
		var encoded_list: Array[String] = payload_string.split(SEPARATOR)
		var packet_list: Array[Packet] = []
		
		for encoded in encoded_list:
			var packet = from_string(encoded)
			
			packet_list.append(packet)
			
			if packet.type == PacketType.ERROR:
				break
		
		return packet_list
	
	func from_string(packet_string: String) -> Packet:
		if _debug:
			print('Decoding string as packet: ' + packet_string)
		
		var packet = Packet.new()
		var type = int(packet_string[0])
		
		if not type in PacketType.values():
			packet.type = PacketType.ERROR
			packet.error = 'Decoded packet type not supported: %s' % type
			
			if _debug:
				push_error(packet.error)
			
			return packet
		
		packet.type = type
		
		if packet_string.length() > 1:
			packet.data = packet_string.substr(1)
		
		if _debug:
			print('String decoded as packet: %s' % packet)
		
		return packet
