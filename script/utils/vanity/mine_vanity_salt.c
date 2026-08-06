/*
 * mine_vanity_salt.c — CREATE3 vanity-address miner for CreateX `deployCreate3`.
 *
 * Mines the low 11 bytes (uint88) of a raw salt so that the address deployed by
 * CreateX (0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed) on behalf of a Gnosis
 * Safe matches a chosen hex prefix/suffix. The deployed address depends ONLY on
 * (CreateX, Safe, low 11 bytes of the raw salt) — contract bytecode and
 * constructor args are irrelevant, and the result is identical on every chain
 * because SaltMath.guardSalt pins byte 20 of the guarded salt to 0x00
 * (CreateX cross-chain mode).
 *
 * Derivation (mirrors forge-deploy-utils SaltMath + CreateX + Create3.sol):
 *   guarded     = safe(20B) ++ 0x00 ++ suffix(11B)
 *   transformed = keccak256( zeros(12B) ++ safe ++ guarded )
 *   proxy       = keccak256( 0xff ++ CreateX ++ transformed ++ PROXY_CHILD_HASH )[12:]
 *   final       = keccak256( 0xd6 0x94 ++ proxy ++ 0x01 )[12:]     // RLP [proxy, nonce 1]
 *
 * All four messages are shorter than the keccak rate (136B), so each candidate
 * costs exactly 3 permutations over pre-padded per-thread blocks.
 *
 * Verify every result independently with script/utils/VerifyVanitySalt.s.sol
 * (uses the production SaltMath) before pasting a salt into Salts.sol.
 *
 * Build/run via the wrapper:  ./mine-vanity-salt.sh [options]
 */
#define _GNU_SOURCE 1

#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#if !defined(__BYTE_ORDER__) || __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "little-endian hosts only (keccak state is copied byte-for-byte)"
#endif
#ifndef __SIZEOF_INT128__
#error "requires a compiler with unsigned __int128 (clang/gcc)"
#endif

typedef unsigned __int128 u128;

/* -------------------------------------------------------------------------- */
/* Constants                                                                  */
/* -------------------------------------------------------------------------- */

/* CreateX factory, same address on all EVM chains. */
static const uint8_t CREATEX_ADDR[20] = {
    0xba, 0x5e, 0xd0, 0x99, 0x63, 0x3d, 0x3b, 0x31, 0x3e, 0x4d,
    0x5f, 0x7b, 0xdc, 0x13, 0x05, 0xd3, 0xc2, 0x8b, 0xa5, 0xed,
};

/* keccak256 of the CREATE3 proxy child bytecode (Create3.sol). */
static const uint8_t PROXY_CHILD_HASH[32] = {
    0x21, 0xc3, 0x5d, 0xbe, 0x1b, 0x34, 0x4a, 0x24, 0x88, 0xcf, 0x33,
    0x21, 0xd6, 0xce, 0x54, 0x2f, 0x8e, 0x9f, 0x30, 0x55, 0x44, 0xff,
    0x09, 0xe4, 0x99, 0x3a, 0x62, 0x31, 0x9a, 0x49, 0x7c, 0x1f,
};

/* Canonical 2/7 mainnet deployer Safe (DEPLOYER_SAFE_ADDRESS in the pipeline). */
#define DEFAULT_SAFE "0x10DC2EFbd84ebFb92eef5f145e3D84CC8b511799"
#define DEFAULT_PREFIX "7e13"
#define DEFAULT_SUFFIX "731"
#define DEFAULT_COUNT 5

#define MAX_THREADS 4096

static const u128 MASK88 = ((u128)1 << 88) - 1;

/* -------------------------------------------------------------------------- */
/* Keccak-256                                                                 */
/* -------------------------------------------------------------------------- */

#define ROTL64(x, n) (((x) << (n)) | ((x) >> (64 - (n))))

static const uint64_t KECCAK_RC[24] = {
    0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
    0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
    0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
    0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
    0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL,
};
static const int KECCAK_ROTC[24] = {1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
                                    27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44};
static const int KECCAK_PILN[24] = {10, 7,  11, 17, 18, 3, 5,  16, 8,  21, 24, 4,
                                    15, 23, 19, 13, 12, 2, 20, 14, 22, 9,  6,  1};

static void keccakf(uint64_t st[25]) {
    for (int round = 0; round < 24; round++) {
        uint64_t bc[5], t;
        /* theta */
        for (int i = 0; i < 5; i++)
            bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];
        for (int i = 0; i < 5; i++) {
            t = bc[(i + 4) % 5] ^ ROTL64(bc[(i + 1) % 5], 1);
            for (int j = 0; j < 25; j += 5)
                st[j + i] ^= t;
        }
        /* rho + pi */
        t = st[1];
        for (int i = 0; i < 24; i++) {
            int j = KECCAK_PILN[i];
            bc[0] = st[j];
            st[j] = ROTL64(t, KECCAK_ROTC[i]);
            t = bc[0];
        }
        /* chi */
        for (int j = 0; j < 25; j += 5) {
            for (int i = 0; i < 5; i++)
                bc[i] = st[j + i];
            for (int i = 0; i < 5; i++)
                st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }
        /* iota */
        st[0] ^= KECCAK_RC[round];
    }
}

/* One-shot keccak256 for messages that fit a single rate block (<= 135 bytes).
 * Ethereum keccak256 pads with 0x01 (original Keccak), NOT SHA3's 0x06.       */
static void keccak256_1block(const uint8_t *msg, size_t len, uint8_t out[32]) {
    uint64_t st[25] = {0};
    uint8_t block[136] = {0};
    if (len > 135) {
        fprintf(stderr, "internal error: keccak256_1block len %zu\n", len);
        abort();
    }
    memcpy(block, msg, len);
    block[len] = 0x01;
    block[135] |= 0x80;
    memcpy(st, block, 136);
    keccakf(st);
    memcpy(out, st, 32);
}

/* -------------------------------------------------------------------------- */
/* Hot-path derivation                                                        */
/* -------------------------------------------------------------------------- */

/* Three persistent pre-padded rate blocks. Per candidate, only the 11 suffix
 * bytes of b1 are rewritten; b2/b3 receive the chained intermediate results.
 * Message ends (keccak pad 0x01) sit at offsets 64 / 85 / 23.                */
typedef struct {
    uint8_t b1[136]; /* zeros(12) ++ safe(20) ++ safe(20) ++ 0x00 ++ suffix(11) */
    uint8_t b2[136]; /* 0xff ++ CreateX(20) ++ transformed(32) ++ childhash(32) */
    uint8_t b3[136]; /* 0xd6 0x94 ++ proxy(20) ++ 0x01                          */
} derive_ctx;

static void derive_init(derive_ctx *c, const uint8_t safe[20]) {
    memset(c, 0, sizeof *c);
    memcpy(c->b1 + 12, safe, 20);
    memcpy(c->b1 + 32, safe, 20);
    /* b1[52] = 0x00: cross-chain byte of the guarded salt; suffix at 53..63 */
    c->b1[64] = 0x01;
    c->b1[135] |= 0x80;

    c->b2[0] = 0xff;
    memcpy(c->b2 + 1, CREATEX_ADDR, 20);
    memcpy(c->b2 + 53, PROXY_CHILD_HASH, 32);
    c->b2[85] = 0x01;
    c->b2[135] |= 0x80;

    c->b3[0] = 0xd6; /* RLP: list, 22 payload bytes */
    c->b3[1] = 0x94; /* RLP: 20-byte string (proxy address) */
    c->b3[22] = 0x01; /* RLP: nonce 1 */
    c->b3[23] = 0x01; /* keccak pad */
    c->b3[135] |= 0x80;
}

/* suffix (11B big-endian) -> deployed address (20B). Exactly 3 permutations. */
static void derive_addr(derive_ctx *c, const uint8_t suffix[11], uint8_t addr[20]) {
    uint64_t st[25];

    memcpy(c->b1 + 53, suffix, 11);
    memcpy(st, c->b1, 136);
    memset((uint8_t *)st + 136, 0, 64);
    keccakf(st);
    memcpy(c->b2 + 21, st, 32); /* transformed salt */

    memcpy(st, c->b2, 136);
    memset((uint8_t *)st + 136, 0, 64);
    keccakf(st);
    memcpy(c->b3 + 2, (uint8_t *)st + 12, 20); /* CREATE3 proxy address */

    memcpy(st, c->b3, 136);
    memset((uint8_t *)st + 136, 0, 64);
    keccakf(st);
    memcpy(addr, (uint8_t *)st + 12, 20); /* final deployed address */
}

/* -------------------------------------------------------------------------- */
/* Hex + EIP-55 helpers                                                       */
/* -------------------------------------------------------------------------- */

static int hexval(int ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

static int hex_decode(const char *hex, size_t nchars, uint8_t *out) {
    if (nchars % 2)
        return -1;
    for (size_t i = 0; i < nchars; i += 2) {
        int hi = hexval(hex[i]), lo = hexval(hex[i + 1]);
        if (hi < 0 || lo < 0)
            return -1;
        out[i / 2] = (uint8_t)((hi << 4) | lo);
    }
    return 0;
}

static void hex_encode(const uint8_t *in, size_t n, char *out) {
    static const char d[] = "0123456789abcdef";
    for (size_t i = 0; i < n; i++) {
        out[2 * i] = d[in[i] >> 4];
        out[2 * i + 1] = d[in[i] & 15];
    }
    out[2 * n] = 0;
}

/* EIP-55: uppercase hex letter i iff nibble i of keccak256(lowercase-hex) >= 8 */
static void format_eip55(const uint8_t addr[20], char out[43]) {
    char lower[41];
    uint8_t h[32];
    hex_encode(addr, 20, lower);
    keccak256_1block((const uint8_t *)lower, 40, h);
    out[0] = '0';
    out[1] = 'x';
    for (int i = 0; i < 40; i++) {
        char ch = lower[i];
        int nib = (h[i / 2] >> (i % 2 ? 0 : 4)) & 0xf;
        if (ch >= 'a' && ch <= 'f' && nib >= 8)
            ch = (char)(ch - 'a' + 'A');
        out[2 + i] = ch;
    }
    out[42] = 0;
}

/* -------------------------------------------------------------------------- */
/* Pattern matching                                                           */
/* -------------------------------------------------------------------------- */

static uint8_t g_want[20], g_mask[20];

static void pattern_set_nibble(size_t pos, int v) {
    size_t byte = pos / 2;
    if (pos % 2 == 0) {
        g_want[byte] |= (uint8_t)(v << 4);
        g_mask[byte] |= 0xf0;
    } else {
        g_want[byte] |= (uint8_t)v;
        g_mask[byte] |= 0x0f;
    }
}

/* Compiles prefix/suffix nibble strings into want/mask. Returns total nibble
 * count, or -1 on invalid input. prefix occupies nibbles [0, np); suffix
 * occupies [40-ns, 40). np+ns <= 40 makes overlap impossible.               */
static int pattern_compile(const char *prefix, const char *suffix) {
    size_t np = strlen(prefix), ns = strlen(suffix);
    if (np + ns == 0 || np + ns > 40)
        return -1;
    memset(g_want, 0, sizeof g_want);
    memset(g_mask, 0, sizeof g_mask);
    for (size_t i = 0; i < np; i++) {
        int v = hexval(prefix[i]);
        if (v < 0)
            return -1;
        pattern_set_nibble(i, v);
    }
    for (size_t j = 0; j < ns; j++) {
        int v = hexval(suffix[j]);
        if (v < 0)
            return -1;
        pattern_set_nibble(40 - ns + j, v);
    }
    return (int)(np + ns);
}

static inline int matches(const uint8_t addr[20]) {
    /* first-byte early exit rejects ~255/256 immediately for a 2+ nibble prefix */
    if ((addr[0] ^ g_want[0]) & g_mask[0])
        return 0;
    for (int i = 1; i < 20; i++)
        if ((addr[i] ^ g_want[i]) & g_mask[i])
            return 0;
    return 1;
}

/* -------------------------------------------------------------------------- */
/* Shared mining state                                                        */
/* -------------------------------------------------------------------------- */

typedef struct {
    _Alignas(64) _Atomic uint64_t tried; /* own cache line, relaxed ops */
    uint8_t pad[56];
} counter_t;

static _Atomic int g_stop;
static _Atomic uint64_t g_found;
static uint64_t g_target = DEFAULT_COUNT;
static pthread_mutex_t g_print_mu = PTHREAD_MUTEX_INITIALIZER;
static counter_t *g_counters;
static int g_nthreads;
static uint8_t g_safe[20];
static int g_safe_is_default = 1;
static const char *g_prefix = DEFAULT_PREFIX;
static const char *g_suffix = DEFAULT_SUFFIX;

static void on_signal(int sig) {
    (void)sig;
    atomic_store(&g_stop, 1);
}

/* -------------------------------------------------------------------------- */
/* Match reporting                                                            */
/* -------------------------------------------------------------------------- */

static void report_match(const uint8_t suffix[11], const uint8_t addr[20]) {
    pthread_mutex_lock(&g_print_mu);
    uint64_t n = atomic_load(&g_found);
    if (n >= g_target) { /* target already reached; drop the extra match */
        pthread_mutex_unlock(&g_print_mu);
        return;
    }
    n++;
    atomic_store(&g_found, n);

    char a55[43], sufhex[23], safehex[41];
    format_eip55(addr, a55);
    hex_encode(suffix, 11, sufhex);
    hex_encode(g_safe, 20, safehex);

    /* rawSalt = 21 zero bytes ++ suffix; guardedSalt = safe ++ 0x00 ++ suffix */
    char rawsalt[65], guarded[65];
    memset(rawsalt, '0', 42);
    memcpy(rawsalt + 42, sufhex, 23); /* 22 hex chars + NUL */
    snprintf(guarded, sizeof guarded, "%s00%s", safehex, sufhex);

    if (isatty(2))
        fputc('\n', stderr); /* break the \r progress line */

    printf("=== match %" PRIu64 "/%" PRIu64 " ===\n", n, g_target);
    printf("address      : %s\n", a55);
    printf("suffix (11B) : 0x%s\n", sufhex);
    printf("rawSalt      : 0x%s\n", rawsalt);
    printf("guardedSalt  : 0x%s\n", guarded);
    printf("Salts.sol    : bytes32 constant TELCOIN_V3_SALT = 0x%s;\n", rawsalt);
    if (g_safe_is_default) {
        printf("verify       : VANITY_SALT=0x%s forge script script/utils/VerifyVanitySalt.s.sol -vvvv\n",
               rawsalt);
    } else {
        printf("verify       : DEPLOYER_SAFE_ADDRESS=0x%s VANITY_SALT=0x%s forge script "
               "script/utils/VerifyVanitySalt.s.sol -vvvv\n",
               safehex, rawsalt);
    }
    printf("\n");
    fflush(stdout);

    if (n >= g_target)
        atomic_store(&g_stop, 1);
    pthread_mutex_unlock(&g_print_mu);
}

/* -------------------------------------------------------------------------- */
/* Workers                                                                    */
/* -------------------------------------------------------------------------- */

typedef struct {
    int id;
    u128 start; /* base + id; stepped by nthreads => disjoint residue classes */
} worker_arg;

static void *worker(void *argp) {
    worker_arg *a = argp;
    derive_ctx ctx;
    derive_init(&ctx, g_safe);
    u128 n = a->start & MASK88;
    uint64_t stride = (uint64_t)g_nthreads;
    uint8_t suffix[11], addr[20];
    uint64_t local = 0;

    while (!atomic_load_explicit(&g_stop, memory_order_relaxed)) {
        for (int i = 0; i < 11; i++)
            suffix[i] = (uint8_t)(n >> (8 * (10 - i))); /* big-endian uint88 */
        derive_addr(&ctx, suffix, addr);
        if (matches(addr))
            report_match(suffix, addr);
        n = (n + stride) & MASK88;
        local++;
        if ((local & 0x3fff) == 0)
            atomic_store_explicit(&g_counters[a->id].tried, local, memory_order_relaxed);
    }
    atomic_store_explicit(&g_counters[a->id].tried, local, memory_order_relaxed);
    return NULL;
}

static uint64_t sum_tried(void) {
    uint64_t total = 0;
    for (int i = 0; i < g_nthreads; i++)
        total += atomic_load_explicit(&g_counters[i].tried, memory_order_relaxed);
    return total;
}

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void fmt_count(double v, char *out, size_t n) {
    if (v < 1e3)
        snprintf(out, n, "%.0f", v);
    else if (v < 1e6)
        snprintf(out, n, "%.1fK", v / 1e3);
    else if (v < 1e9)
        snprintf(out, n, "%.1fM", v / 1e6);
    else if (v < 1e12)
        snprintf(out, n, "%.1fG", v / 1e9);
    else
        snprintf(out, n, "%.2e", v);
}

static void *progress(void *unused) {
    (void)unused;
    double t0 = now_seconds(), last_t = t0;
    uint64_t last_tried = 0;
    while (!atomic_load_explicit(&g_stop, memory_order_relaxed)) {
        /* 2s cadence, sliced so shutdown stays prompt */
        for (int i = 0; i < 20 && !atomic_load_explicit(&g_stop, memory_order_relaxed); i++) {
            struct timespec ts = {0, 100 * 1000 * 1000};
            nanosleep(&ts, NULL);
        }
        if (atomic_load_explicit(&g_stop, memory_order_relaxed))
            break;
        double t = now_seconds();
        uint64_t tried = sum_tried();
        double rate = (double)(tried - last_tried) / (t - last_t);
        char ct[32], cr[32];
        fmt_count((double)tried, ct, sizeof ct);
        fmt_count(rate, cr, sizeof cr);
        fprintf(stderr, "\r[mine] tried %s  %s/s  found %" PRIu64 "/%" PRIu64 "  %.0fs   ",
                ct, cr, atomic_load(&g_found), g_target, t - t0);
        last_tried = tried;
        last_t = t;
    }
    return NULL;
}

/* -------------------------------------------------------------------------- */
/* Self-test                                                                  */
/* -------------------------------------------------------------------------- */

/* Golden vectors: both reproduce live, explorer-verified CreateX deployCreate3
 * deployments (TelcoinV3 V0 on mainnet; TEL v3 testnet). They pin the entire
 * derivation including the keccak pad byte and EIP-55 rendering.             */
static int self_test(void) {
    static const struct {
        const char *safe;
        const char *suffix;
        const char *addr55;
    } V[2] = {
        {"10DC2EFbd84ebFb92eef5f145e3D84CC8b511799", "ba53b2975250769c18dc51",
         "0xE6B8f90D047A4f7294DC6C5E369Ec75EefD62C7b"},
        {"765327d1AeA74cC360B1C6Cc567200d7e4baC3fD", "24e77a99c5af7fcc618069",
         "0x6B46d2f2a27f16dC1ef29a71C38A7E274132C7E7"},
    };
    for (int i = 0; i < 2; i++) {
        uint8_t safe[20], suffix[11], addr[20];
        char a55[43];
        if (hex_decode(V[i].safe, 40, safe) || hex_decode(V[i].suffix, 22, suffix))
            return -1;
        derive_ctx c;
        derive_init(&c, safe);
        derive_addr(&c, suffix, addr);
        format_eip55(addr, a55);
        if (strcmp(a55, V[i].addr55) != 0) {
            fprintf(stderr, "self-test vector %d FAILED: got %s, want %s\n", i + 1, a55,
                    V[i].addr55);
            return -1;
        }
    }
    return 0;
}

/* -------------------------------------------------------------------------- */
/* CLI                                                                        */
/* -------------------------------------------------------------------------- */

static void usage(FILE *to) {
    fprintf(to,
        "usage: mine_vanity_salt [options]\n"
        "\n"
        "Mines the low-11-byte suffix of a CreateX deployCreate3 raw salt so the\n"
        "deployed address matches a hex prefix/suffix (case-insensitive). The address\n"
        "depends only on (CreateX, deployer Safe, salt suffix) — bytecode-independent\n"
        "and identical on every chain.\n"
        "\n"
        "options:\n"
        "  --safe <addr>     deployer Safe (default: canonical mainnet Safe\n"
        "                    " DEFAULT_SAFE ")\n"
        "  --prefix <hex>    required address prefix nibbles after 0x (default: " DEFAULT_PREFIX ")\n"
        "  --suffix <hex>    required address suffix nibbles (default: " DEFAULT_SUFFIX ")\n"
        "                    pass --prefix '' / --suffix '' to drop a side\n"
        "  --threads <n>     worker threads (default: online CPU cores)\n"
        "  --count <n>       stop after n matches (default: %d)\n"
        "  --help            show this help\n"
        "\n"
        "Matches stream to stdout (salt + paste-ready lines); progress goes to stderr.\n"
        "Exit status: 0 if at least one match was found.\n",
        DEFAULT_COUNT);
}

static int parse_safe(const char *s, uint8_t out[20]) {
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
        s += 2;
    if (strlen(s) != 40)
        return -1;
    return hex_decode(s, 40, out);
}

int main(int argc, char **argv) {
    long threads = sysconf(_SC_NPROCESSORS_ONLN);
    if (threads < 1)
        threads = 1;

    static const struct option opts[] = {
        {"safe", required_argument, NULL, 's'},
        {"prefix", required_argument, NULL, 'p'},
        {"suffix", required_argument, NULL, 'x'},
        {"threads", required_argument, NULL, 't'},
        {"count", required_argument, NULL, 'c'},
        {"help", no_argument, NULL, 'h'},
        {0, 0, 0, 0},
    };

    const char *safe_str = DEFAULT_SAFE;
    int opt;
    while ((opt = getopt_long(argc, argv, "", opts, NULL)) != -1) {
        char *end = NULL;
        switch (opt) {
        case 's':
            safe_str = optarg;
            g_safe_is_default = 0;
            break;
        case 'p':
            g_prefix = optarg;
            break;
        case 'x':
            g_suffix = optarg;
            break;
        case 't':
            threads = strtol(optarg, &end, 10);
            if (!end || *end || threads < 1 || threads > MAX_THREADS) {
                fprintf(stderr, "error: --threads must be 1..%d\n\n", MAX_THREADS);
                usage(stderr);
                return 2;
            }
            break;
        case 'c':
            g_target = strtoull(optarg, &end, 10);
            if (!end || *end || g_target < 1) {
                fprintf(stderr, "error: --count must be >= 1\n\n");
                usage(stderr);
                return 2;
            }
            break;
        case 'h':
            usage(stdout);
            return 0;
        default:
            usage(stderr);
            return 2;
        }
    }
    if (optind < argc) {
        fprintf(stderr, "error: unexpected argument '%s'\n\n", argv[optind]);
        usage(stderr);
        return 2;
    }

    if (parse_safe(safe_str, g_safe)) {
        fprintf(stderr, "error: --safe must be a 20-byte hex address, got '%s'\n\n", safe_str);
        usage(stderr);
        return 2;
    }
    int nibbles = pattern_compile(g_prefix, g_suffix);
    if (nibbles < 0) {
        fprintf(stderr,
                "error: bad pattern (prefix '%s', suffix '%s'): hex only, 1..40 nibbles total\n\n",
                g_prefix, g_suffix);
        usage(stderr);
        return 2;
    }
    g_nthreads = (int)threads;

    if (self_test()) {
        fprintf(stderr, "FATAL: self-test failed — refusing to mine with a broken derivation\n");
        return 1;
    }

    char safe55[43];
    format_eip55(g_safe, safe55);
    double expected = 1.0;
    for (int i = 0; i < nibbles; i++)
        expected *= 16.0;
    char cexp[32];
    fmt_count(expected, cexp, sizeof cexp);

    fprintf(stderr, "mine_vanity_salt — CREATE3 vanity miner (CreateX deployCreate3)\n");
    fprintf(stderr, "  deployer Safe : %s%s\n", safe55, g_safe_is_default ? " (canonical)" : "");
    fprintf(stderr, "  pattern       : 0x%s…%s (%d nibbles, ~2^%d = %s candidates/match)\n",
            g_prefix, g_suffix, nibbles, 4 * nibbles, cexp);
    fprintf(stderr, "  threads       : %d   target matches: %" PRIu64 "\n", g_nthreads, g_target);
    fprintf(stderr, "self-test OK (2 vectors)\n");

    /* one shared random 88-bit base; thread t walks base+t, +nthreads, ... */
    u128 base = 0;
    {
        uint8_t rnd[11];
        int fd = open("/dev/urandom", O_RDONLY);
        if (fd < 0 || read(fd, rnd, 11) != 11) {
            fprintf(stderr, "FATAL: cannot read /dev/urandom: %s\n", strerror(errno));
            return 1;
        }
        close(fd);
        for (int i = 0; i < 11; i++)
            base = (base << 8) | rnd[i];
    }

    g_counters = aligned_alloc(64, (size_t)g_nthreads * sizeof(counter_t));
    worker_arg *args = calloc((size_t)g_nthreads, sizeof(worker_arg));
    pthread_t *tids = calloc((size_t)g_nthreads, sizeof(pthread_t));
    if (!g_counters || !args || !tids) {
        fprintf(stderr, "FATAL: out of memory\n");
        return 1;
    }
    memset(g_counters, 0, (size_t)g_nthreads * sizeof(counter_t));

    struct sigaction sa = {0};
    sa.sa_handler = on_signal;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    double t0 = now_seconds();
    for (int i = 0; i < g_nthreads; i++) {
        args[i].id = i;
        args[i].start = base + (u128)i;
        if (pthread_create(&tids[i], NULL, worker, &args[i])) {
            fprintf(stderr, "FATAL: pthread_create failed\n");
            return 1;
        }
    }
    pthread_t prog;
    int have_prog = pthread_create(&prog, NULL, progress, NULL) == 0;

    for (int i = 0; i < g_nthreads; i++)
        pthread_join(tids[i], NULL);
    atomic_store(&g_stop, 1);
    if (have_prog)
        pthread_join(prog, NULL);

    double dt = now_seconds() - t0;
    uint64_t tried = sum_tried();
    uint64_t found = atomic_load(&g_found);
    char ct[32], cr[32];
    fmt_count((double)tried, ct, sizeof ct);
    fmt_count(dt > 0 ? (double)tried / dt : 0, cr, sizeof cr);
    fprintf(stderr, "\n[done] tried %s in %.1fs (%s/s), found %" PRIu64 " match(es)\n", ct, dt, cr,
            found);

    free(tids);
    free(args);
    free(g_counters);
    return found > 0 ? 0 : 1;
}
