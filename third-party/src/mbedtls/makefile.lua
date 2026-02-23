--------------------------------------------------------------------------------
-- INFORMATION                                                                --
--------------------------------------------------------------------------------

--
-- Compile as static libraries
--
-- History
-- mbedtls-4.0.0 (the release tarball, NOT the GIT source tree)
--
-- The GIT source tree is split between tf-psa-crypto and mbedtls
-- But the release tarball embed the tf-psa-crypto dependancy.
--

--------------------------------------------------------------------------------
-- CHECK                                                                      --
--------------------------------------------------------------------------------

---@diagnostic disable: undefined-global

--------------------------------------------------------------------------------
-- HELPERS                                                                    --
--------------------------------------------------------------------------------

local function SourceToObject (Pathname)
  local Filename   = filename(Pathname)
  local Basename   = removeext(Filename, ".c")
  local ObjectName = format("bin/%s.o", Basename)
  return nativepath(ObjectName)
end

local function makeflags (FlagsTable)
  local FlagsString = concat(FlagsTable, " ")
  return FlagsString
end

local function CompileCommand (FlagsTable, SourceFilename, ObjectFilename)
  local FlagsString = makeflags(FlagsTable)
  return format("\t$(CC) %s -c %s -o %s", FlagsString, SourceFilename, ObjectFilename)
end

local function header (Pathname)
  local NativePathname = nativepath(Pathname)
  return format("-I%s", NativePathname)
end

local function appendrules (Rules, FlagsTable, Sources, Objects)
  for Index, Source in ipairs(Sources) do
    local Object = Objects[Index]
    append(Rules, format("%s: %s", Object, Source))
    append(Rules, CompileCommand(FlagsTable, Source, Object))
    append(Rules, "")
  end
  return Rules
end

local function finalizerules (Rules)
  -- Remove all the empty lines at the end
  while (#Rules > 0) and (Rules[#Rules] == "") do
    Rules[#Rules] = nil
  end
  -- New lines
  return concat(Rules, "\n")
end

--------------------------------------------------------------------------------
-- CONFIGURATION                                                              --
--------------------------------------------------------------------------------

local GENERIC_Flags = {
  "-ggdb",
  "-fvisibility=hidden",
  "--std=c99",
  "-Wall",
  "-Wextra",
}

local PROJECT_Flags = {
  "-Os",
}

if (HOST == "windows") and (TARGET == "windows") then
  append(PROJECT_Flags, "-fdiagnostics-color=never")
end

-- We have a patch to implement thread safety using libuv mutexes
-- in third-party\src\mbedtls\src\tf-psa-crypto\include\mbedtls\threading_alt.h
local LIBUV_Includes = {
  header("../libuv/include"),
}

--------------------------------------------------------------------------------
-- TF-PSA-CRYPTO                                                              --
--------------------------------------------------------------------------------

local CryptoSources = {
  -- src/tf-psa-crypto/drivers/builtin/src
  "src/tf-psa-crypto/drivers/builtin/src/aes.c",
  "src/tf-psa-crypto/drivers/builtin/src/aesce.c",
  "src/tf-psa-crypto/drivers/builtin/src/aesni.c",
  "src/tf-psa-crypto/drivers/builtin/src/aria.c",
  "src/tf-psa-crypto/drivers/builtin/src/asn1parse.c",
  "src/tf-psa-crypto/drivers/builtin/src/asn1write.c",
  "src/tf-psa-crypto/drivers/builtin/src/base64.c",
  "src/tf-psa-crypto/drivers/builtin/src/bignum.c",
  "src/tf-psa-crypto/drivers/builtin/src/bignum_core.c",
  "src/tf-psa-crypto/drivers/builtin/src/bignum_mod.c",
  "src/tf-psa-crypto/drivers/builtin/src/bignum_mod_raw.c",
  "src/tf-psa-crypto/drivers/builtin/src/block_cipher.c",
  "src/tf-psa-crypto/drivers/builtin/src/camellia.c",
  "src/tf-psa-crypto/drivers/builtin/src/ccm.c",
  "src/tf-psa-crypto/drivers/builtin/src/chacha20.c",
  "src/tf-psa-crypto/drivers/builtin/src/chachapoly.c",
  "src/tf-psa-crypto/drivers/builtin/src/cipher.c",
  "src/tf-psa-crypto/drivers/builtin/src/cipher_wrap.c",
  "src/tf-psa-crypto/drivers/builtin/src/cmac.c",
  "src/tf-psa-crypto/drivers/builtin/src/constant_time.c",
  "src/tf-psa-crypto/drivers/builtin/src/ctr_drbg.c",
  "src/tf-psa-crypto/drivers/builtin/src/ecdh.c",
  "src/tf-psa-crypto/drivers/builtin/src/ecdsa.c",
  "src/tf-psa-crypto/drivers/builtin/src/ecjpake.c",
  "src/tf-psa-crypto/drivers/builtin/src/ecp.c",
  "src/tf-psa-crypto/drivers/builtin/src/ecp_curves.c",
  "src/tf-psa-crypto/drivers/builtin/src/ecp_curves_new.c",
  "src/tf-psa-crypto/drivers/builtin/src/entropy.c",
  "src/tf-psa-crypto/drivers/builtin/src/entropy_poll.c",
  "src/tf-psa-crypto/drivers/builtin/src/gcm.c",
  "src/tf-psa-crypto/drivers/builtin/src/hmac_drbg.c",
  "src/tf-psa-crypto/drivers/builtin/src/lmots.c",
  "src/tf-psa-crypto/drivers/builtin/src/lms.c",
  "src/tf-psa-crypto/drivers/builtin/src/md.c",
  "src/tf-psa-crypto/drivers/builtin/src/md5.c",
  "src/tf-psa-crypto/drivers/builtin/src/memory_buffer_alloc.c",
  "src/tf-psa-crypto/drivers/builtin/src/nist_kw.c",
  "src/tf-psa-crypto/drivers/builtin/src/oid.c",
  "src/tf-psa-crypto/drivers/builtin/src/pem.c",
  "src/tf-psa-crypto/drivers/builtin/src/pk.c",
  "src/tf-psa-crypto/drivers/builtin/src/pk_ecc.c",
  "src/tf-psa-crypto/drivers/builtin/src/pk_rsa.c",
  "src/tf-psa-crypto/drivers/builtin/src/pk_wrap.c",
  "src/tf-psa-crypto/drivers/builtin/src/pkcs5.c",
  "src/tf-psa-crypto/drivers/builtin/src/pkparse.c",
  "src/tf-psa-crypto/drivers/builtin/src/pkwrite.c",
  "src/tf-psa-crypto/drivers/builtin/src/platform.c",
  "src/tf-psa-crypto/drivers/builtin/src/platform_util.c",
  "src/tf-psa-crypto/drivers/builtin/src/poly1305.c",
  "src/tf-psa-crypto/drivers/builtin/src/psa_crypto_aead.c",
  "src/tf-psa-crypto/drivers/builtin/src/psa_crypto_cipher.c",
  "src/tf-psa-crypto/drivers/builtin/src/psa_crypto_ecp.c",
  "src/tf-psa-crypto/drivers/builtin/src/psa_crypto_ffdh.c",
  "src/tf-psa-crypto/drivers/builtin/src/psa_crypto_hash.c",
  "src/tf-psa-crypto/drivers/builtin/src/psa_crypto_mac.c",
  "src/tf-psa-crypto/drivers/builtin/src/psa_crypto_pake.c",
  "src/tf-psa-crypto/drivers/builtin/src/psa_crypto_rsa.c",
  "src/tf-psa-crypto/drivers/builtin/src/psa_util.c",
  "src/tf-psa-crypto/drivers/builtin/src/ripemd160.c",
  "src/tf-psa-crypto/drivers/builtin/src/rsa.c",
  "src/tf-psa-crypto/drivers/builtin/src/rsa_alt_helpers.c",
  "src/tf-psa-crypto/drivers/builtin/src/sha1.c",
  "src/tf-psa-crypto/drivers/builtin/src/sha256.c",
  "src/tf-psa-crypto/drivers/builtin/src/sha3.c",
  "src/tf-psa-crypto/drivers/builtin/src/sha512.c",
  "src/tf-psa-crypto/drivers/builtin/src/threading.c",
  -- Everest
  "src/tf-psa-crypto/drivers/everest/library/everest.c",
  "src/tf-psa-crypto/drivers/everest/library/x25519.c",
  "src/tf-psa-crypto/drivers/everest/library/Hacl_Curve25519_joined.c",
  -- P256-m
  "src/tf-psa-crypto/drivers/p256-m/p256-m_driver_entrypoints.c",
  "src/tf-psa-crypto/drivers/p256-m/p256-m/p256-m.c",
  -- Core
  "src/tf-psa-crypto/core/psa_crypto.c",
  "src/tf-psa-crypto/core/psa_crypto_client.c",
  "src/tf-psa-crypto/core/psa_crypto_driver_wrappers_no_static.c",
  "src/tf-psa-crypto/core/psa_crypto_slot_management.c",
  "src/tf-psa-crypto/core/psa_crypto_storage.c",
  "src/tf-psa-crypto/core/psa_its_file.c",
  "src/tf-psa-crypto/core/tf_psa_crypto_config.c",
  "src/tf-psa-crypto/core/tf_psa_crypto_version.c",
}

local CryptoFlags = {
  header("src/tf-psa-crypto/include"),
  header("src/tf-psa-crypto/core"),
  header("src/tf-psa-crypto/drivers/builtin/include"),
  header("src/tf-psa-crypto/drivers/everest/include/tf-psa-crypto/private/everest"),
  header("src/tf-psa-crypto/drivers/builtin/src"),
}

if (TARGET == "linux") then
  append(CryptoFlags, "-D_GNU_SOURCE")
  append(CryptoFlags, "-D_FILE_OFFSET_BIT=64")
  append(CryptoFlags, "-D_LARGEFILE_SOURCE")
  append(CryptoFlags, "-pthread")
end

--------------------------------------------------------------------------------
-- MBEDTLS                                                                    --
--------------------------------------------------------------------------------

local MbedtlsSources = {
  "src/library/debug.c",
  "src/library/error.c",
  "src/library/mbedtls_config.c",
  "src/library/mps_reader.c",
  "src/library/mps_trace.c",
  "src/library/net_sockets.c",
  "src/library/pkcs7.c",
  "src/library/ssl_cache.c",
  "src/library/ssl_ciphersuites.c",
  "src/library/ssl_client.c",
  "src/library/ssl_cookie.c",
  "src/library/ssl_debug_helpers_generated.c",
  "src/library/ssl_msg.c",
  "src/library/ssl_ticket.c",
  "src/library/ssl_tls12_client.c",
  "src/library/ssl_tls12_server.c",
  "src/library/ssl_tls13_client.c",
  "src/library/ssl_tls13_generic.c",
  "src/library/ssl_tls13_keys.c",
  "src/library/ssl_tls13_server.c",
  "src/library/ssl_tls.c",
  "src/library/timing.c",
  "src/library/version.c",
  "src/library/version_features.c",
  "src/library/x509.c",
  "src/library/x509_create.c",
  "src/library/x509_crl.c",
  "src/library/x509_crt.c",
  "src/library/x509_csr.c",
  "src/library/x509_oid.c",
  "src/library/x509write.c",
  "src/library/x509write_crt.c",
  "src/library/x509write_csr.c",
}

local MbedtlsFlags = {
  header("include"),
  header("src/tf-psa-crypto/core"),
  header("src/tf-psa-crypto/include"),
  header("src/tf-psa-crypto/drivers/builtin/include"),
  header("src/tf-psa-crypto/drivers/builtin/src"),
  header("src/library"),
  "-Wno-format",
}

if (TARGET == "linux") then
  append(MbedtlsFlags, "-D_GNU_SOURCE")
  append(MbedtlsFlags, "-D_FILE_OFFSET_BIT=64")
  append(MbedtlsFlags, "-D_LARGEFILE_SOURCE")
  append(MbedtlsFlags, "-pthread")
end

--------------------------------------------------------------------------------
-- LOCAL DATA                                                                 --
--------------------------------------------------------------------------------

local Rules = {}

-- tf-psa-crypto
local NativeCryptoSources = map(CryptoSources, nativepath)
local CryptoObjects       = map(NativeCryptoSources, SourceToObject)
local CryptoFlagsTable    = mergetables(GENERIC_Flags, PROJECT_Flags, LIBUV_Includes, CryptoFlags)

appendrules(Rules, CryptoFlagsTable, NativeCryptoSources, CryptoObjects)

-- mbedtls
local NativeMbedtlsSources = map(MbedtlsSources, nativepath)
local MbedtlsObjects       = map(NativeMbedtlsSources, SourceToObject)
local MbedtlsFlagsTable    = mergetables(GENERIC_Flags, PROJECT_Flags, LIBUV_Includes, MbedtlsFlags)

appendrules(Rules, MbedtlsFlagsTable, NativeMbedtlsSources, MbedtlsObjects)

--------------------------------------------------------------------------------
-- MAKEFILE                                                                   --
--------------------------------------------------------------------------------

local Environment = {
  RULES           = finalizerules(Rules),
  CRYPTO_OBJECTS  = concat(CryptoObjects, " "),
  MBEDTLS_OBJECTS = concat(MbedtlsObjects, " "),
  LIBCRYPTO_LIB   = nativepath("bin/libtfpsacrypto.a"),
  LIBMBEDTLS_LIB  = nativepath("bin/libmbedtls.a"),
  RM              = RM,
}

local MakefileTemplate = [[
.PHONY: all clean

all: $LIBCRYPTO_LIB $LIBMBEDTLS_LIB

$RULES

$LIBCRYPTO_LIB: $CRYPTO_OBJECTS
	ar rcs $@ $^

$LIBMBEDTLS_LIB: $MBEDTLS_OBJECTS
	ar rcs $@ $^

clean:
	$RM $CRYPTO_OBJECTS $MBEDTLS_OBJECTS $LIBCRYPTO_LIB $LIBMBEDTLS_LIB
  ]]

generate(Environment, MakefileTemplate)
