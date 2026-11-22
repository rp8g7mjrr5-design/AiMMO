class_name CryptoUtil
## Small crypto helpers built on Godot's native SHA-256 and HMAC.

static var _crypto: Crypto


static func _c() -> Crypto:
	if _crypto == null:
		_crypto = Crypto.new()
	return _crypto


static func random_bytes(n: int) -> PackedByteArray:
	return _c().generate_random_bytes(n)


static func sha256(data: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish()


static func hmac_sha256(key: PackedByteArray, msg: PackedByteArray) -> PackedByteArray:
	return _c().hmac_digest(HashingContext.HASH_SHA256, key, msg)


static func xor_bytes(a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(a.size())
	for i in a.size():
		out[i] = a[i] ^ b[i]
	return out


## PBKDF2-HMAC-SHA256 with a 32-byte output (one block), as used by SCRAM-SHA-256.
static func pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := hmac_sha256(password, block)
	var acc := u.duplicate()
	for _i in range(1, iterations):
		u = hmac_sha256(password, u)
		for j in acc.size():
			acc[j] ^= u[j]
	return acc


# --- player passwords ---

const PASSWORD_ITERATIONS := 20000


## Returns "pbkdf2_sha256$<iterations>$<salt b64>$<hash b64>".
static func hash_password(password: String, iterations: int = PASSWORD_ITERATIONS) -> String:
	var salt := random_bytes(16)
	var dk := pbkdf2_sha256(password.to_utf8_buffer(), salt, iterations)
	return "pbkdf2_sha256$%d$%s$%s" % [iterations, Marshalls.raw_to_base64(salt), Marshalls.raw_to_base64(dk)]


static func verify_password(password: String, stored: String) -> bool:
	var parts := stored.split("$")
	if parts.size() != 4 or parts[0] != "pbkdf2_sha256":
		return false
	var iterations := parts[1].to_int()
	if iterations < 1:
		return false
	var salt := Marshalls.base64_to_raw(parts[2])
	var expected := Marshalls.base64_to_raw(parts[3])
	var got := pbkdf2_sha256(password.to_utf8_buffer(), salt, iterations)
	return constant_time_equal(got, expected)


static func constant_time_equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0
