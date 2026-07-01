# frozen_string_literal: true

require 'uri'

namespace :breakers do
  desc <<~DESC
    Validate that Common::Client::Configuration::* classes are breakers-eligible.

    Each class is checked for:
      1. Inheritance from Common::Client::Configuration::REST or ::SOAP
      2. A `service_name` that returns a non-empty string
      3. A `base_path` that returns a URI-parseable value (direct method or delegate)
      4. The :breakers middleware wired into its Faraday connection stack
         (only enforced if the class defines its own `connection` method)

    Configs that authenticate dynamically (i.e. define `get_access_token`) are
    treated as a distinct "OAuth handshake" category rather than checked against
    the four criteria above -- they exist purely to fetch a token via client-
    credentials flow and typically have no `connection`/`base_path`/static
    `service_name` of their own. See the OAUTH HANDSHAKE CONFIGS output section.

    By default, classes that pass cleanly (or land in an informational category)
    are shown as a single compact line. Set VERBOSE=1 to see the full true/false
    breakdown of all four checks for every class, in every section.

    Examples:
      bundle exec rake breakers:validate                              # check every descendant
      bundle exec rake "breakers:validate[Chip::Configuration]"       # check one class
      bundle exec rake "breakers:validate[Chip::Configuration,VBS::Configuration]"
                                                                      # check multiple (note quotes)
      VERBOSE=1 bundle exec rake breakers:validate                    # full detail for everything
      VERBOSE=1 bundle exec rake "breakers:validate[Chip::Configuration]"
                                                                      # full detail for one class
  DESC
  task :validate, [:targets] => :environment do |_t, args|
    Rails.application.eager_load!

    verbose = ENV['VERBOSE'].present?

    classes_to_check =
      if args[:targets].blank?
        Common::Client::Configuration::Base.descendants.uniq.sort_by(&:name)
      else
        names = ([args[:targets]] + args.extras).flat_map { |s| s.to_s.split(',') }
        names.map(&:strip).reject(&:empty?).map(&:constantize)
      end

    summary = { pass: [], fail: [], abstract: [], oauth_handshake: [], service_name_matched: [] }

    # Find direct subclasses of each class so we can identify abstract bases
    # (classes that exist only so other configs can inherit from them).
    all_classes = Common::Client::Configuration::Base.descendants.uniq
    subclass_count = Hash.new(0)
    all_classes.each { |c| subclass_count[c.superclass] += 1 }
    framework_bases = [
      defined?(Common::Client::Configuration::REST) ? Common::Client::Configuration::REST : nil,
      defined?(Common::Client::Configuration::SOAP) ? Common::Client::Configuration::SOAP : nil
    ].compact

    results = []
    classes_to_check.each do |klass|
      inh_ok, inh_detail   = check_inheritance(klass)
      name_ok, name_detail = check_service_name(klass)
      path_ok, path_detail = check_base_path(klass)
      mw_ok, mw_detail     = check_breakers_middleware(klass)

      all_ok = inh_ok && name_ok && path_ok && mw_ok

      # An "abstract base" is a class that doesn't implement its own
      # service_name or base_path BUT has subclasses that do. The script
      # would otherwise flag these as failures, but they're intentional --
      # the audit only wants to surface them informationally.
      is_framework_base = framework_bases.include?(klass)
      is_abstract = !all_ok && (is_framework_base || (subclass_count[klass].positive? && !name_ok && !path_ok))

      # An "oauth handshake" config defines `get_access_token` and exists
      # purely to perform a client-credentials token exchange. These configs
      # legitimately have no `connection`, `base_path`, or static
      # `service_name` -- the real HTTP client that consumes the token (and
      # makes the actual API calls) is often a separate, hand-rolled Faraday
      # client elsewhere in the codebase that this audit cannot see, since
      # it isn't a Common::Client::Configuration::Base descendant. Treat
      # these as their own category rather than failures.
      is_oauth_handshake = !all_ok && !is_abstract && dynamic_credentials_config?(klass)

      # A "service_name-matched" config: inheritance, service_name, and
      # :breakers middleware all pass -- only base_path fails. Breakers can
      # match requests by service_name (when the middleware is wired with
      # `service_name:`) or by URL host/port/path (the base_path fallback).
      # When `service_name:` is passed, base_path is never exercised at
      # request-match time. These configs typically use alternative URL
      # accessors like `api_url`, `access_token_url`, etc.
      # NOTE: registering these in breakers.rb still requires adding a
      # base_path accessor, since registration calls
      # `breakers_service` -> `URI.parse(base_path)`.
      is_service_name_matched = !is_abstract && !is_oauth_handshake &&
                                inh_ok && name_ok && mw_ok && !path_ok

      results << {
        klass:,
        passed: all_ok,
        abstract: is_abstract,
        oauth_handshake: is_oauth_handshake,
        service_name_matched: is_service_name_matched,
        subclass_count: subclass_count[klass],
        checks: {
          inheritance: [inh_ok, inh_detail],
          service_name: [name_ok, name_detail],
          base_path: [path_ok, path_detail],
          breakers_middleware: [mw_ok, mw_detail]
        }
      }
    rescue Exception => e # rubocop:disable Lint/RescueException
      # Catch literally anything (including ScriptError, SystemExit, etc.)
      # so one broken class doesn't abort the rest of the audit.
      results << { klass:, passed: false, abstract: false, oauth_handshake: false,
                   service_name_matched: false, error: e }
    end

    passes = results.select { |r| r[:passed] }
    abstracts = results.select { |r| !r[:passed] && r[:abstract] }
    oauth_handshake = results.select { |r| !r[:passed] && !r[:abstract] && r[:oauth_handshake] }
    service_name_matched = results.select do |r|
      !r[:passed] && !r[:abstract] && !r[:oauth_handshake] && r[:service_name_matched]
    end
    failures = results.select do |r|
      !r[:passed] && !r[:abstract] && !r[:oauth_handshake] && !r[:service_name_matched]
    end

    if verbose
      puts '═' * 80
      puts "PASSES (#{passes.size})"
      puts '═' * 80
    end
    passes.each do |r|
      if verbose
        print_verbose_block(r)
      else
        puts "✅ #{r[:klass].name}"
      end
      summary[:pass] << r[:klass].name
    end

    unless abstracts.empty?
      puts
      puts '═' * 80
      puts "ABSTRACT BASE CLASSES (#{abstracts.size}) -- informational, not action items"
      puts '═' * 80
      puts 'These classes exist so other configs can inherit shared connection logic.'
      puts 'They have no service_name or base_path of their own by design and should'
      puts 'NOT be registered in config/initializers/breakers.rb directly.'
      puts

      abstracts.each do |r|
        subs = r[:subclass_count]
        suffix = subs.positive? ? "#{subs} subclass#{'es' if subs != 1}" : 'framework base'
        if verbose
          print_verbose_block(r, note: suffix)
        else
          puts "ℹ️  #{r[:klass].name} (#{suffix})"
        end
      end
    end

    unless oauth_handshake.empty?
      puts
      puts '═' * 80
      puts "OAUTH HANDSHAKE CONFIGS (#{oauth_handshake.size}) -- informational, not action items"
      puts '═' * 80
      puts 'These configs define `get_access_token` and exist purely to perform a'
      puts 'client-credentials OAuth token exchange. They have no `connection`,'
      puts '`base_path`, or static `service_name` of their own by design.'
      puts
      puts 'IMPORTANT: the real HTTP client that consumes this token to make actual'
      puts 'API calls is often a separate, hand-rolled Faraday client elsewhere in the'
      puts 'codebase (e.g. lib/bd/bd.rb, lib/fes_service/base.rb). This audit cannot'
      puts 'see those clients, since they are not Common::Client::Configuration::Base'
      puts 'descendants. Check manually that any such client wires in'
      puts '`faraday.use(:breakers, service_name:)` -- this script cannot verify that'
      puts 'for you.'
      puts

      oauth_handshake.each do |r|
        if verbose
          print_verbose_block(r)
        else
          puts "ℹ️  #{r[:klass].name}"
        end
      end
    end

    unless service_name_matched.empty?
      puts
      puts '═' * 80
      puts "SERVICE_NAME-MATCHED CONFIGS (#{service_name_matched.size}) -- informational, not action items"
      puts '═' * 80
      puts 'These configs do not define `base_path` because Breakers identifies'
      puts 'their requests by `service_name` (passed explicitly to the middleware)'
      puts 'rather than by URL host/port/path. The missing base_path is intentional;'
      puts 'these configs typically use alternative URL accessors like `api_url`,'
      puts '`access_token_url`, etc.'
      puts
      puts 'NOTE: registering these in breakers.rb still requires adding a base_path'
      puts 'accessor (even a one-liner aliasing api_url), because registration calls'
      puts 'breakers_service -> URI.parse(base_path).'
      puts

      service_name_matched.each do |r|
        if verbose
          print_verbose_block(r)
        else
          puts "ℹ️  #{r[:klass].name}"
        end
      end
    end

    unless failures.empty?
      puts
      puts '═' * 80
      puts "FAILURES (#{failures.size})"
      puts '═' * 80

      failures.each do |r|
        if r[:error]
          puts
          puts r[:klass].name
          puts "  ❌ unexpected #{r[:error].class}: #{r[:error].message}"
          puts "     #{r[:error].backtrace.first(3).join("\n     ")}"
        else
          print_verbose_block(r)
        end
        summary[:fail] << r[:klass].name
      end
    end

    abstracts.each { |r| summary[:abstract] << r[:klass].name }
    oauth_handshake.each { |r| summary[:oauth_handshake] << r[:klass].name }
    service_name_matched.each { |r| summary[:service_name_matched] << r[:klass].name }

    puts
    puts '─' * 80
    puts "PASS: #{summary[:pass].size}    " \
         "ABSTRACT: #{summary[:abstract].size}    " \
         "OAUTH: #{summary[:oauth_handshake].size}    " \
         "SERVICE_NAME-MATCHED: #{summary[:service_name_matched].size}    " \
         "FAIL: #{summary[:fail].size}"

    if summary[:fail].any?
      puts
      puts 'Failed classes:'
      summary[:fail].each { |n| puts "  - #{n}" }
      abort # non-zero exit so CI can use this as a gate
    end
  end

  # --- helpers -------------------------------------------------------------

  def format_label(key)
    {
      inheritance: 'inheritance         ',
      service_name: 'service_name        ',
      base_path: 'base_path           ',
      breakers_middleware: ':breakers middleware'
    }.fetch(key, key.to_s)
  end

  def status_line(label, ok, detail = nil)
    mark = ok ? '✅' : '❌'
    line = "  #{mark} #{label}"
    line += " -- #{detail}" if detail
    line
  end

  # Prints the class name followed by the true/false + detail for all four
  # checks. Used for VERBOSE mode in every section, and always for FAILURES
  # (which have always shown full detail, verbose or not).
  def print_verbose_block(result, note: nil)
    puts
    puts "#{result[:klass].name}#{note ? " (#{note})" : ''}"
    result[:checks].each do |label, (ok, detail)|
      puts status_line(format_label(label), ok, detail)
    end
  end

  # Configs that authenticate dynamically (token exchange, OAuth-style flows)
  # define `get_access_token` and don't have a static service_name/base_path
  # to check -- they're not abstract bases, they're just a different pattern.
  def dynamic_credentials_config?(klass)
    klass.instance_methods.include?(:get_access_token)
  end

  def check_inheritance(klass)
    rest = defined?(Common::Client::Configuration::REST) && klass < Common::Client::Configuration::REST
    soap = defined?(Common::Client::Configuration::SOAP) && klass < Common::Client::Configuration::SOAP
    base = defined?(Common::Client::Configuration::Base) && klass <= Common::Client::Configuration::Base

    if rest
      [true, 'inherits from Common::Client::Configuration::REST']
    elsif soap
      [true, 'inherits from Common::Client::Configuration::SOAP']
    elsif base
      # The class IS Common::Client::Configuration::Base/REST/SOAP itself,
      # or inherits from Base directly (skipping REST/SOAP). Direct-Base
      # inheritance is unusual -- the codebase convention is to go through
      # REST or SOAP so the format-specific defaults (JSON headers, SOAP SSL,
      # etc.) are applied.
      msg =
        if klass == Common::Client::Configuration::Base
          'is Common::Client::Configuration::Base itself (framework base)'
        else
          "inherits from #{klass.superclass.name} directly -- should inherit from " \
            'Common::Client::Configuration::REST or ::SOAP instead'
        end
      [false, msg]
    else
      [false, "inherits from #{klass.superclass.name} (not a recognized Common::Client::Configuration::* ancestor)"]
    end
  end

  def check_service_name(klass)
    return [false, 'class does not respond to .instance (not a Singleton?)'] unless klass.respond_to?(:instance)

    # Use .send so we can read private methods. Some configs make
    # service_name private; Breakers reads it via instance_eval, so private
    # is valid in practice.
    value = klass.instance.send(:service_name)
    if value.is_a?(String) && !value.strip.empty?
      [true, value.inspect]
    else
      [false, "returned #{value.inspect}"]
    end
  rescue NotImplementedError
    if dynamic_credentials_config?(klass)
      [true, 'dynamic service name (defines get_access_token)']
    else
      [false, 'raises NotImplementedError (abstract base or missing override)']
    end
  rescue => e
    [false, "raised #{e.class}: #{e.message}"]
  end

  def check_base_path(klass)
    return [false, 'class does not respond to .instance'] unless klass.respond_to?(:instance)

    # Use .send so we can read private `base_path` methods. Some configs
    # (CARMA, SSOe) make it private, but Breakers calls it from inside a
    # matcher proc that has access to private methods via instance_eval --
    # so private here is valid in practice.
    value = klass.instance.send(:base_path)
    if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      [false, "returned #{value.inspect} -- likely a missing Settings key"]
    else
      URI.parse(value.to_s) # raises if not parseable
      [true, value.to_s]
    end
  rescue NotImplementedError
    if dynamic_credentials_config?(klass)
      [true, 'base_path not applicable (defines get_access_token)']
    else
      [false, 'raises NotImplementedError (abstract base or missing override)']
    end
  rescue URI::InvalidURIError => e
    [false, "URI.parse failed: #{e.message}"]
  rescue => e
    [false, "raised #{e.class}: #{e.message}"]
  end

  def check_breakers_middleware(klass)
    inherited = inherited_connection_result(klass)
    return inherited if inherited

    return [false, 'class does not respond to .instance'] unless klass.respond_to?(:instance)

    conn = klass.instance.connection
    handlers = conn.builder.handlers.map(&:name)
    if handlers.include?('Breakers::UptimeMiddleware')
      [true, 'Breakers::UptimeMiddleware present in Faraday stack']
    else
      [false, "no Breakers::UptimeMiddleware in stack. Handlers: #{handlers.join(', ')}"]
    end
  rescue NotImplementedError
    if dynamic_credentials_config?(klass)
      [true, 'connection not evaluated (defines get_access_token)']
    else
      [false, 'connection raised NotImplementedError (likely abstract base)']
    end
  rescue => e
    # NOTE: RuntimeError is a StandardError subclass and is already caught
    # here -- no separate `rescue RuntimeError` needed.
    [false, "could not build connection (#{e.class}: #{e.message})"]
  end

  # Returns nil if `klass` defines its own `connection` (the caller should
  # check it normally). Otherwise returns a [ok, detail] tuple: [true, ...]
  # if some ancestor defines `connection` (so the parent's check already
  # covers this), or [false, ...] if NO ancestor defines one either. Note:
  # a [false, ...] here for a dynamic-credentials config (get_access_token)
  # is expected and gets reclassified into the OAUTH HANDSHAKE section by
  # the caller's top-level categorization -- it is not silently hidden.
  def inherited_connection_result(klass)
    return nil if klass.instance_methods(false).include?(:connection)

    parent_with_conn = klass.ancestors[1..].find { |a| a.instance_methods(false).include?(:connection) }
    if parent_with_conn
      [true, "inherits connection from #{parent_with_conn.name} (skip)"]
    else
      [false, 'does not define connection, and no ancestor provides one']
    end
  end
end
