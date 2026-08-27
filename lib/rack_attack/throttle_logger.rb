# frozen_string_literal: true

require 'ipaddr'
require 'openssl'
require 'resolv'

# NOTE: `RackAttack` (this module) is deliberately distinct from `Rack::Attack`
# (the gem). We avoid reopening the gem namespace so this diagnostic code stays
# self-contained and obviously ours.
module RackAttack
  # Logs structured diagnostics for every Rack::Attack throttle (HTTP 429).
  #
  # Subscribed to the `throttle.rack_attack` ActiveSupport::Notifications event,
  # which the rack-attack gem fires ONLY when a request exceeds a throttle limit
  # (see Rack::Attack::Throttle#call -> `Rack::Attack.instrument` is called inside
  # `if throttled`). That makes this cheap: it runs per-429, not per-request.
  #
  # Why: rate-limit buckets are keyed on the throttle discriminator (usually
  # `req.remote_ip`). If many clients collapse onto one discriminator value -- a
  # shared proxy/CGNAT hop, or a shared X-Real-IP from an incomplete revproxy
  # `set_real_ip_from` -- a single bucket fills and unrelated users get 429s
  # after only a few requests. Logging the REMOTE_ADDR / X-Real-IP /
  # X-Forwarded-For alongside the computed discriminator makes that collapse
  # visible: if one discriminator keeps recurring while the X-Forwarded-For
  # client hops behind it differ, the discriminator is the bug, not the traffic.
  #
  # No IP is ever logged in the clear. Each is replaced by a keyed pseudonym --
  # `ip_<16 hex>` for the address and `net_<16 hex>` for its enclosing network --
  # so equality is preserved (same IP always yields the same token, which is what
  # makes collapse visible) while the address itself is not recoverable from the
  # log. See `token` for why this is keyed rather than a bare SHA256.
  #
  # Gated behind the `rack_attack_throttle_logging` Flipper flag (default off).
  # Calling Flipper here is safe: this runs at request time, inside the executor
  # (Rack::Attack is appended to the middleware stack via `config.middleware.use`,
  # so it runs after AR connection management), long after boot -- unlike the
  # rack_attack.rb initializer body, where Flipper is not yet configured.
  module ThrottleLogger
    FLAG = :rack_attack_throttle_logging

    # Hex characters kept from each HMAC digest. 16 hex = 64 bits.
    #
    # This is a readability bound, not a security one -- the key already provides
    # the irreversibility. It is sized against COLLISIONS, because a collision here
    # would print two different IPs as the same token, manufacturing exactly the
    # false "these clients share a bucket" signal this diagnostic exists to detect.
    # By the birthday bound, 64 bits gives a ~3-in-10-million chance of a single
    # collision across 10M distinct addresses in a window; you would have to hash
    # most of the IPv4 internet before one became likely. (48 bits, by contrast,
    # collides ~18% of the time at 10M addresses -- far too loose for this use.)
    TOKEN_LENGTH = 16

    # Domain-separation label mixed into every digest, so a token minted here can
    # never equal a token minted elsewhere from the same key and the same input.
    HASH_DOMAIN = 'rack_attack_throttle_log'

    # Network sizes used for the `net_` token: the smallest blocks that are still
    # meaningfully "one operator's allocation". /24 is the longest IPv4 prefix
    # normally routed on the public internet; /48 is the standard IPv6 site
    # assignment. A shared `net_` under differing `ip_` values is subnet spray;
    # a single repeated `ip_` is one host.
    IPV4_PREFIX_BITS = 24
    IPV6_PREFIX_BITS = 48

    # Returned in place of a token when a field that should hold an IP does not.
    # We deliberately do NOT fall through to logging the raw value: an unparseable
    # REMOTE_ADDR or X-Forwarded-For hop is attacker-controlled input, and echoing
    # it into the log is how you get log injection.
    INVALID_IP = '[invalid_ip]'

    # Keys whose values are pseudonymized IPs. Passed as `safe_keys` so the
    # semantic_logger PII scrubber leaves them intact -- tokens don't match its IP
    # regexes anyway, but this is explicit belt-and-suspenders.
    SAFE_KEYS = %i[remote_addr x_real_ip x_forwarded_for x_forwarded_for_client
                   discriminator discriminator_net computed_remote_ip hash_key_id].freeze

    module_function

    # @param request [Rack::Attack::Request] the throttled request from the
    #   `throttle.rack_attack` notification payload
    def log(request)
      return unless Flipper.enabled?(FLAG)

      # Only log IP-discriminator throttles. This diagnostic exists to surface
      # IP-discriminator collapse (many clients sharing one IP bucket), so a
      # non-IP discriminator has nothing to tell us here. Most rules key on
      # `req.remote_ip`, but some don't -- e.g. the next_steps_email throttle
      # keys on a SHA256 of the recipient email -- and those we skip.
      return unless ip_like?(request.env['rack.attack.match_discriminator'])

      Rails.logger.info('RackAttack throttled request', diagnostics(request))
      StatsD.increment('rack_attack.throttled', tags: ["rule:#{request.env['rack.attack.matched']}"])
    rescue => e
      # Never let diagnostics affect the request path.
      Rails.logger.error('RackAttack::ThrottleLogger failed', exception: e)
    end

    # True when `value` is an IPv4 or IPv6 address. Rejects nil and non-IP
    # discriminators (e.g. a SHA256 hex digest). Uses Resolv's anchored address
    # regex rather than `IPAddr.new` so the reject path is allocation-free and
    # avoids exception-based control flow -- this runs per-429, and during the
    # discriminator collapse this diagnostic exists to catch, that can be millions.
    def ip_like?(value)
      value && Resolv::AddressRegex.match?(value.to_s)
    end

    def diagnostics(request)
      env = request.env
      match_data = env['rack.attack.match_data'] || {}
      discriminator = env['rack.attack.match_discriminator']

      {
        rule: env['rack.attack.matched'],
        discriminator: mask_ip(discriminator),
        discriminator_net: mask_network(discriminator),
        computed_remote_ip: mask_ip(computed_remote_ip(request)),
        remote_addr: mask_ip(env['REMOTE_ADDR']),
        x_real_ip: mask_ip(env['HTTP_X_REAL_IP']),
        hash_key_id:,
        path: request.path,
        request_method: request.request_method,
        count: match_data[:count],
        limit: match_data[:limit],
        period: match_data[:period],
        safe_keys: SAFE_KEYS
      }.merge(forwarding_diagnostics(env['HTTP_X_FORWARDED_FOR'], mask_ip(discriminator)))
    end

    # The X-Forwarded-For fields, split out so the chain can be queried rather
    # than eyeballed as one string.
    #
    # @param header [String, nil] raw X-Forwarded-For
    # @param discriminator [String, nil] the already-masked throttle discriminator
    def forwarding_diagnostics(header, discriminator)
      hops = mask_ip_list(header)

      {
        # Where in the chain the throttle bucket was drawn from. 0 means we
        # bucketed on the hop nearest the client, which is what we want; a
        # consistently non-zero index means we are bucketing on a proxy, and every
        # client behind that proxy shares its limit. nil means the discriminator
        # isn't in the chain at all (no XFF, or it came from REMOTE_ADDR).
        discriminator_hop: hops&.index(discriminator),
        # The hop nearest the client. Its own field so it can be counted and
        # grouped in the log aggregator: `discriminator` holding steady while
        # distinct values of this pile up behind it IS the collapse. Untrusted --
        # the leftmost hop is caller-supplied and forgeable -- so treat a wide
        # spread here as a lead, not proof.
        x_forwarded_for_client: hops&.first,
        x_forwarded_for: hops&.join(', '),
        x_forwarded_for_hops: hops&.length
      }
    end

    # The IP our custom Rack::Attack::Request#remote_ip resolves to. For IP-based
    # throttles this equals the discriminator; logging both surfaces the rare case
    # where they diverge (e.g. rules that key on something other than remote_ip).
    def computed_remote_ip(request)
      request.remote_ip if request.respond_to?(:remote_ip)
    rescue
      nil
    end

    # Pseudonymize an address: `203.0.113.5` -> `ip_9f3a1c04b7de5a81`.
    # Returns nil for nil so absent headers stay absent rather than becoming noise.
    def mask_ip(value)
      return nil if value.nil?
      return INVALID_IP unless ip_like?(value.to_s.strip)

      token('ip', canonical_ip(value.to_s.strip))
    end

    # Pseudonymize the network containing an address: every host in 203.0.113.0/24
    # yields the same `net_` token. This is what preserves the signal that plain
    # full-address hashing would lose -- without it, "one host hammering" and
    # "a whole subnet spraying" are indistinguishable, since both just look like
    # tokens you have never seen before.
    def mask_network(value)
      return nil if value.nil?
      return INVALID_IP unless ip_like?(value.to_s.strip)

      ip = IPAddr.new(value.to_s.strip)
      token('net', ip.mask(ip.ipv4? ? IPV4_PREFIX_BITS : IPV6_PREFIX_BITS).to_s)
    rescue IPAddr::Error
      INVALID_IP
    end

    # X-Forwarded-For is a comma-separated chain of hops, ordered client-first.
    # Pseudonymize each one and KEEP THE WHOLE CHAIN, in order.
    #
    # Retaining the hops that sit ahead of the throttled address is the point: our
    # revproxy picks one of them as X-Real-IP, and if `set_real_ip_from` doesn't
    # cover every hop it can pick a proxy instead of the client. When that happens
    # the discriminator is identical for everyone behind that proxy while these
    # earlier hops still differ -- so the chain is the evidence that distinguishes
    # "one client is hammering us" from "we merged a crowd into one bucket".
    #
    # @return [Array<String>, nil] masked hops, client-first
    def mask_ip_list(value)
      return nil if value.nil?

      value.to_s.split(',').map { |hop| mask_ip(hop.strip) }
    end

    # Normalize before hashing so two spellings of one address can't produce two
    # tokens -- e.g. `2001:DB8::1`, `2001:db8::1`, and `2001:db8:0:0:0:0:0:1` are
    # all the same host, and if they tokenized differently the log would imply
    # three clients where there is one. Falls back to the input on anything IPAddr
    # rejects -- reachable, because Resolv's regex is looser than IPAddr for
    # compressed IPv6 (`1:2:3:4:5:6:7:8::9` has nine groups: regex yes, IPAddr no).
    # The fallback still gets hashed, so the raw value never reaches the log.
    def canonical_ip(str)
      IPAddr.new(str).to_s
    rescue IPAddr::Error
      str
    end

    # Keyed pseudonym for `value`, prefixed so the log says what kind of thing it
    # stands for.
    #
    # HMAC rather than a bare SHA256 because IPv4 is only 2**32 addresses: an
    # unkeyed digest of an IP is reversible by exhaustive search in minutes, so it
    # would obfuscate the address from a casual reader and from nobody else. The
    # key makes the mapping recoverable only by someone who holds the key, which
    # is what lets these tokens sit in a log aggregator. (Contrast the
    # next_steps_email throttle's bare `Digest::SHA256` of an email address --
    # sound there precisely because the email space is not enumerable.)
    #
    # `prefix` is hashed as well as printed, so the ip_ and net_ namespaces are
    # genuinely disjoint. Without that they alias on network addresses -- a /24 is
    # masked to `203.0.113.0`, which is also a real host, so `ip_` and `net_` would
    # print the same digest for it and quietly reveal that the address ends in .0.
    def token(prefix, value)
      digest = OpenSSL::HMAC.hexdigest('SHA256', hash_key, "#{HASH_DOMAIN}|#{prefix}|#{value}")
      "#{prefix}_#{digest[0, TOKEN_LENGTH]}"
    end

    # The HMAC key. Sourced per-environment from Parameter Store
    # (`env_vars/rack_attack/throttle_log/hash_secret`) so dev, sandbox, staging
    # and production mint disjoint token namespaces and no one can carry a token
    # from a lower environment into production.
    #
    # Falls back to `secret_key_base` -- itself per-environment, high-entropy and
    # never logged -- when the parameter is unset. The fallback exists so the
    # diagnostic still works on a review instance or a fresh checkout: failing
    # closed here would mean the flag turns on during an incident and silently
    # produces nothing.
    def hash_key
      Settings.rack_attack&.throttle_log&.hash_secret.presence || Rails.application.secret_key_base
    end

    # Short fingerprint of the key in play, logged on every line.
    #
    # Tokens are only comparable within one key. Rotating the secret (or reading
    # logs that span a rotation, or span two environments) remints every token,
    # which would otherwise read as "the entire client population turned over" --
    # the exact opposite of the truth. When this value changes, the token
    # namespace changed; don't compare across the boundary. Derived through the
    # HMAC so it reveals nothing about the key itself.
    def hash_key_id
      OpenSSL::HMAC.hexdigest('SHA256', hash_key, "#{HASH_DOMAIN}|key_id")[0, 8]
    end
  end
end
