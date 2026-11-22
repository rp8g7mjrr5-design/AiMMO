extends TestCase


func test_pbkdf2_known_vectors() -> void:
	# PBKDF2-HMAC-SHA256 vectors (RFC 7914 style, P="password", S="salt").
	var p := "password".to_utf8_buffer()
	var s := "salt".to_utf8_buffer()
	check_eq(CryptoUtil.pbkdf2_sha256(p, s, 1).hex_encode(), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", "c=1")
	check_eq(CryptoUtil.pbkdf2_sha256(p, s, 2).hex_encode(), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43", "c=2")
	check_eq(CryptoUtil.pbkdf2_sha256(p, s, 4096).hex_encode(), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", "c=4096")


func test_password_roundtrip() -> void:
	var h := CryptoUtil.hash_password("hunter22", 50)
	check(h.begins_with("pbkdf2_sha256$50$"), "format")
	check(CryptoUtil.verify_password("hunter22", h), "right password verifies")
	check(not CryptoUtil.verify_password("hunter23", h), "wrong password rejected")
	check(not CryptoUtil.verify_password("hunter22", "garbage"), "garbage hash rejected")
	check(CryptoUtil.hash_password("same", 50) != CryptoUtil.hash_password("same", 50), "salted")
