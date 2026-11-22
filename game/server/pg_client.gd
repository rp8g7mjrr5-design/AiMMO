class_name PgClient
extends RefCounted
## Minimal PostgreSQL client speaking the v3 wire protocol over TCP (optionally TLS).
## Supports cleartext, MD5, and SCRAM-SHA-256 auth, simple queries (for migrations), and
## parameterised queries via the extended protocol (for everything with player input).
## Calls are blocking. Results are Arrays of Dictionaries of Strings (text format), or
## null values for SQL NULL.

var last_error := ""
var timeout_ms := 10000

var _tcp: StreamPeerTCP
var _stream: StreamPeer
var _buf := PackedByteArray()
var _connected := false


## Parses postgres://user:pass@host:port/dbname?sslmode=require
## sslmode defaults to "disable": Railway's private network (the default DATABASE_URL)
## is not TLS. "prefer" tries TLS and falls back to plain; "require" insists on TLS.
static func parse_url(url: String) -> Dictionary:
	var out := {"user": "", "password": "", "host": "127.0.0.1", "port": 5432, "database": "", "sslmode": "disable"}
	var u := url.strip_edges()
	for scheme in ["postgresql://", "postgres://"]:
		if u.begins_with(scheme):
			u = u.substr(scheme.length())
			break
	var q := u.find("?")
	if q != -1:
		for pair in u.substr(q + 1).split("&"):
			var kv := pair.split("=")
			if kv.size() == 2 and kv[0] == "sslmode":
				out.sslmode = kv[1]
		u = u.substr(0, q)
	var at := u.rfind("@")
	if at != -1:
		var cred := u.substr(0, at)
		u = u.substr(at + 1)
		var c := cred.find(":")
		if c == -1:
			out.user = cred.uri_decode()
		else:
			out.user = cred.substr(0, c).uri_decode()
			out.password = cred.substr(c + 1).uri_decode()
	var slash := u.find("/")
	if slash != -1:
		out.database = u.substr(slash + 1).uri_decode()
		u = u.substr(0, slash)
	var colon := u.rfind(":")
	if colon != -1:
		out.port = u.substr(colon + 1).to_int()
		u = u.substr(0, colon)
	if u != "":
		out.host = u
	if out.database == "":
		out.database = out.user
	return out


func connect_url(url: String) -> bool:
	var cfg := parse_url(url)
	return connect_to(cfg.host, cfg.port, cfg.user, cfg.password, cfg.database, cfg.sslmode)


func connect_to(host: String, port: int, user: String, password: String, database: String, sslmode: String = "prefer") -> bool:
	last_error = ""
	_buf.clear()
	_tcp = StreamPeerTCP.new()
	_tcp.big_endian = true
	var ip := host
	if not host.is_valid_ip_address():
		ip = IP.resolve_hostname(host)
		if ip == "":
			return _fail("could not resolve host %s" % host)
	if _tcp.connect_to_host(ip, port) != OK:
		return _fail("could not start connection to %s:%d" % [host, port])
	var deadline := Time.get_ticks_msec() + timeout_ms
	while true:
		_tcp.poll()
		var st := _tcp.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			break
		if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
			return _fail("connection to %s:%d failed" % [host, port])
		if Time.get_ticks_msec() > deadline:
			return _fail("connection to %s:%d timed out" % [host, port])
		OS.delay_msec(2)
	_stream = _tcp

	if sslmode != "disable":
		if not _negotiate_tls(host, sslmode):
			if sslmode == "prefer":
				return connect_to(host, port, user, password, database, "disable")
			return false

	var body := PackedByteArray()
	body.append_array(_i32(196608))
	for kv in [["user", user], ["database", database], ["application_name", "aimmo-server"], ["client_encoding", "UTF8"]]:
		body.append_array(_cstr(kv[0]))
		body.append_array(_cstr(kv[1]))
	body.append(0)
	var msg := _i32(body.size() + 4)
	msg.append_array(body)
	if not _send(msg):
		return false
	if not _authenticate(user, password):
		return false
	# Drain ParameterStatus / BackendKeyData until ReadyForQuery.
	while true:
		var m := _read_message()
		if m.is_empty():
			return false
		if m.type == "Z":
			break
		if m.type == "E":
			return _fail(_parse_error(m.body))
	_connected = true
	return true


func is_connected_to_db() -> bool:
	if not _connected or _tcp == null:
		return false
	_tcp.poll()
	return _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


func close() -> void:
	if _stream != null and _connected:
		_send(PackedByteArray([88, 0, 0, 0, 4])) # 'X' Terminate
	if _stream is StreamPeerTLS:
		(_stream as StreamPeerTLS).disconnect_from_stream()
	if _tcp != null:
		_tcp.disconnect_from_host()
	_connected = false


## Runs one or more statements with no parameters. Returns rows of the last statement,
## or null on error (see last_error).
func simple_query(sql: String) -> Variant:
	var msg := PackedByteArray([81]) # 'Q'
	var s := _cstr(sql)
	msg.append_array(_i32(s.size() + 4))
	msg.append_array(s)
	if not _send(msg):
		return null
	return _collect_results()


## Runs one parameterised statement. Params are converted to text; null stays NULL.
## Returns an Array of row Dictionaries, or null on error.
func query(sql: String, params: Array = []) -> Variant:
	var out := PackedByteArray()
	# Parse (unnamed statement)
	var p := _cstr("")
	p.append_array(_cstr(sql))
	p.append_array(_i16(0))
	out.append_array(_frame(80, p))
	# Bind (unnamed portal, all params text, all results text)
	var b := _cstr("")
	b.append_array(_cstr(""))
	b.append_array(_i16(0))
	b.append_array(_i16(params.size()))
	for v in params:
		if v == null:
			b.append_array(_i32(-1))
		else:
			var bytes := _to_text(v).to_utf8_buffer()
			b.append_array(_i32(bytes.size()))
			b.append_array(bytes)
	b.append_array(_i16(0))
	out.append_array(_frame(66, b))
	# Describe portal, Execute, Sync
	var d := PackedByteArray([80])
	d.append_array(_cstr(""))
	out.append_array(_frame(68, d))
	var e := _cstr("")
	e.append_array(_i32(0))
	out.append_array(_frame(69, e))
	out.append_array(_frame(83, PackedByteArray()))
	if not _send(out):
		return null
	return _collect_results()


# --- internals ---

func _collect_results() -> Variant:
	var columns: Array = []
	var rows: Array = []
	var err := ""
	while true:
		var m := _read_message()
		if m.is_empty():
			_connected = false
			return null
		match m.type:
			"T":
				columns = _parse_row_description(m.body)
				rows = []
			"D":
				rows.append(_parse_data_row(m.body, columns))
			"E":
				err = _parse_error(m.body)
			"Z":
				break
			_:
				pass # 1, 2, C, n, N, S, I: nothing to do
	if err != "":
		last_error = err
		return null
	return rows


func _negotiate_tls(host: String, sslmode: String) -> bool:
	if not _send(_i32(8) + _i32(80877103)):
		return false
	var r := _read_exact(1)
	if r.is_empty():
		return false
	if r[0] != 83: # 'S'
		if sslmode == "require" or sslmode.begins_with("verify"):
			return _fail("server refused TLS but sslmode=%s" % sslmode)
		return true
	var tls := StreamPeerTLS.new()
	var opts := TLSOptions.client() if sslmode.begins_with("verify") else TLSOptions.client_unsafe()
	if tls.connect_to_stream(_tcp, host, opts) != OK:
		return _fail("TLS setup failed")
	var deadline := Time.get_ticks_msec() + timeout_ms
	while true:
		tls.poll()
		var st := tls.get_status()
		if st == StreamPeerTLS.STATUS_CONNECTED:
			break
		if st != StreamPeerTLS.STATUS_HANDSHAKING:
			return _fail("TLS handshake failed")
		if Time.get_ticks_msec() > deadline:
			return _fail("TLS handshake timed out")
		OS.delay_msec(2)
	_stream = tls
	return true


func _authenticate(user: String, password: String) -> bool:
	var nonce := ""
	var client_first_bare := ""
	var server_sig := PackedByteArray()
	while true:
		var m := _read_message()
		if m.is_empty():
			return false
		if m.type == "E":
			return _fail(_parse_error(m.body))
		if m.type != "R":
			return _fail("unexpected message during auth: %s" % m.type)
		var code: int = _be32(m.body, 0)
		match code:
			0:
				return true
			3:
				var pw := _cstr(password)
				if not _send(_frame(112, pw)):
					return false
			5:
				var salt: PackedByteArray = m.body.slice(4, 8)
				var inner := (password + user).md5_text()
				var h := PackedByteArray(inner.to_utf8_buffer())
				h.append_array(salt)
				var outer := "md5" + _md5_hex(h)
				if not _send(_frame(112, _cstr(outer))):
					return false
			10:
				if not _sasl_mechanisms(m.body.slice(4)).has("SCRAM-SHA-256"):
					return _fail("server offers no supported SASL mechanism")
				nonce = Marshalls.raw_to_base64(CryptoUtil.random_bytes(18))
				client_first_bare = "n=,r=" + nonce
				var first := ("n,," + client_first_bare).to_utf8_buffer()
				var body := _cstr("SCRAM-SHA-256")
				body.append_array(_i32(first.size()))
				body.append_array(first)
				if not _send(_frame(112, body)):
					return false
			11:
				var server_first: String = m.body.slice(4).get_string_from_utf8()
				var attrs := _scram_attrs(server_first)
				if not str(attrs.get("r", "")).begins_with(nonce):
					return _fail("SCRAM nonce mismatch")
				var salt: PackedByteArray = Marshalls.base64_to_raw(attrs.get("s", ""))
				var iters := str(attrs.get("i", "4096")).to_int()
				var salted := CryptoUtil.pbkdf2_sha256(password.to_utf8_buffer(), salt, iters)
				var client_key := CryptoUtil.hmac_sha256(salted, "Client Key".to_utf8_buffer())
				var stored_key := CryptoUtil.sha256(client_key)
				var without_proof := "c=biws,r=" + str(attrs.r)
				var auth_msg: PackedByteArray = (client_first_bare + "," + server_first + "," + without_proof).to_utf8_buffer()
				var client_sig := CryptoUtil.hmac_sha256(stored_key, auth_msg)
				var proof := CryptoUtil.xor_bytes(client_key, client_sig)
				var server_key := CryptoUtil.hmac_sha256(salted, "Server Key".to_utf8_buffer())
				server_sig = CryptoUtil.hmac_sha256(server_key, auth_msg)
				var final := (without_proof + ",p=" + Marshalls.raw_to_base64(proof)).to_utf8_buffer()
				if not _send(_frame(112, final)):
					return false
			12:
				var attrs := _scram_attrs(m.body.slice(4).get_string_from_utf8())
				var v := Marshalls.base64_to_raw(attrs.get("v", ""))
				if not CryptoUtil.constant_time_equal(v, server_sig):
					return _fail("SCRAM server signature mismatch")
			_:
				return _fail("unsupported auth method %d" % code)
	return false


func _poll() -> void:
	if _stream is StreamPeerTLS:
		(_stream as StreamPeerTLS).poll()
	else:
		_tcp.poll()


func _sasl_mechanisms(b: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	var start := 0
	for i in b.size():
		if b[i] == 0:
			if i > start:
				out.append(b.slice(start, i).get_string_from_utf8())
			start = i + 1
	return out


func _md5_hex(data: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(data)
	return h.finish().hex_encode()


func _scram_attrs(s: String) -> Dictionary:
	var out := {}
	for part in s.split(","):
		if part.length() >= 2 and part[1] == "=":
			out[part[0]] = part.substr(2)
	return out


func _parse_row_description(body: PackedByteArray) -> Array:
	var n := _be16(body, 0)
	var off := 2
	var cols: Array = []
	for _i in n:
		var end := off
		while body[end] != 0:
			end += 1
		cols.append(body.slice(off, end).get_string_from_utf8())
		off = end + 1 + 18
	return cols


func _parse_data_row(body: PackedByteArray, cols: Array) -> Dictionary:
	var n := _be16(body, 0)
	var off := 2
	var row := {}
	for i in n:
		var length := _be32s(body, off)
		off += 4
		var key: String = cols[i] if i < cols.size() else str(i)
		if length < 0:
			row[key] = null
		else:
			row[key] = body.slice(off, off + length).get_string_from_utf8()
			off += length
	return row


func _parse_error(body: PackedByteArray) -> String:
	var fields := {}
	var off := 0
	while off < body.size() and body[off] != 0:
		var code := char(body[off])
		var end := off + 1
		while end < body.size() and body[end] != 0:
			end += 1
		fields[code] = body.slice(off + 1, end).get_string_from_utf8()
		off = end + 1
	return "%s %s: %s" % [fields.get("S", "ERROR"), fields.get("C", "?????"), fields.get("M", "unknown error")]


func _read_message() -> Dictionary:
	var head := _read_exact(5)
	if head.is_empty():
		return {}
	var length := _be32(head, 1)
	var body := PackedByteArray()
	if length > 4:
		body = _read_exact(length - 4)
		if body.is_empty():
			return {}
	return {"type": char(head[0]), "body": body}


func _read_exact(n: int) -> PackedByteArray:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while _buf.size() < n:
		_poll()
		var avail := _stream.get_available_bytes()
		if avail > 0:
			var r := _stream.get_partial_data(avail)
			if r[0] != OK:
				_fail("read failed")
				return PackedByteArray()
			_buf.append_array(r[1])
			continue
		if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_fail("connection closed by server")
			return PackedByteArray()
		if Time.get_ticks_msec() > deadline:
			_fail("read timed out")
			return PackedByteArray()
		OS.delay_usec(300)
	var out := _buf.slice(0, n)
	_buf = _buf.slice(n)
	return out


func _send(data: PackedByteArray) -> bool:
	var off := 0
	var deadline := Time.get_ticks_msec() + timeout_ms
	while off < data.size():
		var r := _stream.put_partial_data(data.slice(off))
		if r[0] != OK:
			return _fail("write failed")
		off += int(r[1])
		if off < data.size():
			if Time.get_ticks_msec() > deadline:
				return _fail("write timed out")
			_poll()
			OS.delay_usec(300)
	return true


func _fail(msg: String) -> bool:
	last_error = msg
	_connected = false
	return false


func _frame(type_byte: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([type_byte])
	out.append_array(_i32(body.size() + 4))
	out.append_array(body)
	return out


func _to_text(v: Variant) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_FLOAT:
			return String.num(v, 6) if is_finite(v) else "0"
		_:
			return str(v)


static func _cstr(s: String) -> PackedByteArray:
	var b := s.to_utf8_buffer()
	b.append(0)
	return b


static func _i32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])


static func _i16(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 8) & 0xFF, v & 0xFF])


static func _be32(b: PackedByteArray, off: int) -> int:
	return (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3]


static func _be32s(b: PackedByteArray, off: int) -> int:
	var v := _be32(b, off)
	return v - 0x100000000 if v >= 0x80000000 else v


static func _be16(b: PackedByteArray, off: int) -> int:
	return (b[off] << 8) | b[off + 1]
