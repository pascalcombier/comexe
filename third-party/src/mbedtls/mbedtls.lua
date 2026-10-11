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
-- SOURCES                                                                    --
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

--------------------------------------------------------------------------------
-- FLAGS                                                                      --
--------------------------------------------------------------------------------

local GenericFlags = {
  "-ggdb",
  "-fvisibility=hidden",
  "--std=c99",
  "-Wall",
  "-Wextra",
  "-flto",
}

-- Component flags (shared)
local ComponentFlags = {
  "-Os",
  "-target $TRIPLE",
}

local LibuvIncludeFlags = {
  "-I$Pthird-party/src/libuv/include",
}

-- CryptoSources include flags
local CryptoIncludeFlags = {
  "-I$P$DIR/src/tf-psa-crypto/include",
  "-I$P$DIR/src/tf-psa-crypto/core",
  "-I$P$DIR/src/tf-psa-crypto/drivers/builtin/include",
  "-I$P$DIR/src/tf-psa-crypto/drivers/everest/include/tf-psa-crypto/private/everest",
  "-I$P$DIR/src/tf-psa-crypto/drivers/builtin/src",
}

-- MbedtlsSources include flags
local MbedtlsIncludeFlags = {
  "-I$P$DIR/include",
  "-I$P$DIR/src/tf-psa-crypto/core",
  "-I$P$DIR/src/tf-psa-crypto/include",
  "-I$P$DIR/src/tf-psa-crypto/drivers/builtin/include",
  "-I$P$DIR/src/tf-psa-crypto/drivers/builtin/src",
  "-I$P$DIR/src/library",
  "-Wno-format",
}

local LinuxFlags = {
  "-D_GNU_SOURCE",
  "-D_FILE_OFFSET_BIT=64",
  "-D_LARGEFILE_SOURCE",
  "-pthread",
}

--------------------------------------------------------------------------------
-- BUILD RENDERER                                                             --
--------------------------------------------------------------------------------

local function Render (Environment)
  -- Return rule output (for map call)
  local function RuleOutput (Rule)
    return Rule.Out
  end
  -- Evaluate final flags
  local OsFlags
  if (Environment.OS == "linux") then
    OsFlags = LinuxFlags
  else
    OsFlags = {}
  end
  local BuildCryptoFlags  = merge(GenericFlags, ComponentFlags, LibuvIncludeFlags, CryptoIncludeFlags, OsFlags)
  local BuildMbedtlsFlags = merge(GenericFlags, ComponentFlags, LibuvIncludeFlags, MbedtlsIncludeFlags, OsFlags)
  -- Create a RULE for a crypto source file
  local function MakeCryptoRule (Source)
    local FlagsString = concat(BuildCryptoFlags, " ")
    local Path        = format("$DIR/%s", Source)
    local Name, Basename, Extension = newpathname(Path):getname()
    assert((Extension == "c"), format("source is not a C file (got %q)", Path))
    local NewRule = {
      Ins = { Path },
      Run = { format("zig cc %s -c $IN -o $OUT", FlagsString) },
      Out = format("bin/$TRIPLE/$NAME/%s.o", Basename),
    }
    return NewRule
  end
  -- Create a RULE for a library source file
  local function MakeMbedtlsRule (Source)
    local FlagsString = concat(BuildMbedtlsFlags, " ")
    local Path        = format("$DIR/%s", Source)
    local Name, Basename, Extension = newpathname(Path):getname()
    assert((Extension == "c"), format("source is not a C file (got %q)", Path))
    local NewRule = {
      Ins = { Path },
      Run = { format("zig cc %s -c $IN -o $OUT", FlagsString) },
      Out = format("bin/$TRIPLE/$NAME/%s.o", Basename),
    }
    return NewRule
  end
  -- Create a specific target for each source file
  local CryptoRules  = map(CryptoSources,  MakeCryptoRule)
  local MbedtlsRules = map(MbedtlsSources, MakeMbedtlsRule)
  local CompileRules = merge(CryptoRules,  MbedtlsRules)
  -- Retrieve objects files from Rules[Index].Out
  local CryptoObjectList  = map(CryptoRules,  RuleOutput)
  local MbedtlsObjectList = map(MbedtlsRules, RuleOutput)
  -- Rule to build the archive
  local ArchiveRules = {
    {
      Ins = CryptoObjectList,
      Run = { "zig ar rcs $OUT $INS" },
      Out = "bin/$TRIPLE/$NAME/libtfpsacrypto.a",
    },
    {
      Ins = MbedtlsObjectList,
      Run = { "zig ar rcs $OUT $INS" },
      Out = "bin/$TRIPLE/$NAME/libmbedtls.a",
    },
  }
  -- Gather all the rules
  local Result = {
    Rules     = merge(CompileRules, ArchiveRules),
    Artifacts = {
      ArchiveRules[1].Out,
      ArchiveRules[2].Out,
    },
  }
  return Result
end

return Render
