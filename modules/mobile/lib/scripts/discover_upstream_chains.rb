# frozen_string_literal: true

# Boot the Rails env to use Zeitwerk autoloading for
# constant to file resolution via Module.const_source_location
require_relative '../../../../config/environment'
require 'prism'

# This script traces call chains from mobile controllers through proxies/services
# to external upstream services, showing full dependency path:
#
#   Controller → Proxy → External Service
#
# It uses Prism to parse Ruby files and Rails' Zeitwerk autoloader
# to resolve constants to their source files.
#
# Usage:
#   bundle exec ruby modules/mobile/lib/scripts/discover_upstream_chains.rb
#
# Output:
#   JSON object with:
#   - dependency_chains: call paths from each controller to external services
#   - unresolved: constants that could not be resolved to a file

class DiscoverUpstreamChains
  MOBILE_ROOT = File.expand_path('../..', __dir__)
  VETS_API_ROOT = File.expand_path('../../../..', __dir__)
  CONFIG_PATH = File.join(__dir__, 'config', 'upstream_services.yml')

  SCAN_DIR = File.join(MOBILE_ROOT, 'app', 'controllers')

  # Only follow classes whose names end with these suffixes.
  # Other .new calls (structs, adapters, errors) are not upstream services
  SERVICE_SUFFIXES = /(?:Service|Client|Proxy|Manager|Provider|Downloader)\z/

  # Method names that indicate service instantiation.
  INSTANTIATION_METHODS = %i[new build].freeze

  def initialize(output_file: nil)
    config = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
    @upstream_groups = config['upstream_groups'] || {}
    @excluded_classes = config['excluded_classes'] || []
    @unresolved = []
    @output_file = output_file
  end

  def run
    chains = discover_all_chains
    output_json(chains)
  end

  private

  # Entry Point - Iterate All Controllers

  # Scans every controller file and traces its service dependencies
  # through proxies down to external services.
  def discover_all_chains
    controller_glob = File.join(SCAN_DIR, '**', '*.rb')
    Dir.glob(controller_glob)
       .reject { |path| path.split('/').include?('concerns') }
       .filter_map { |path| build_chain_entry(path) }
  end

  # Builds a chain entry for a single controller file.
  # Returns a hash with endpoint, feature, and chains, or nil if no chains found.
  def build_chain_entry(controller_path)
    relative_path = controller_path.sub("#{MOBILE_ROOT}/", '')
    feature_name = feature_name_from_path(relative_path)

    instantiations = find_instantiations_in_file(controller_path)
    instantiations = find_inherited_instantiations(controller_path) if instantiations.empty?
    return if instantiations.empty?

    chains = instantiations.flat_map do |inst|
      trace_chain(
        constant_name: inst[:constant],
        source_file: controller_path,
        visited: Set.new,
        chain_so_far: []
      )
    end

    return if chains.empty?

    { endpoint: relative_path, feature: feature_name, chains: chains.uniq }
  end

  # AST Parsing

  # Visits call nodes in a Prism AST and collects service class instantiations
  class InstantiationFinder < Prism::Visitor
    attr_reader :instantiations

    def initialize(service_suffixes, excluded_classes)
      super()
      @service_suffixes = service_suffixes
      @excluded_classes = excluded_classes
      @instantiations = []
    end

    # Called for every method call node (ex: SomeService.new, SomeClient.build)
    def visit_call_node(node)
      if INSTANTIATION_METHODS.include?(node.name)
        receiver = node.receiver
        constant_name = constant_name_from(receiver)
        suffix_match = constant_name&.match?(@service_suffixes)
        allowed = @excluded_classes.exclude?(constant_name)
        should_include = suffix_match && allowed
        @instantiations << { constant: constant_name } if should_include
      end

      super # continue walking children
    end

    private

    # Extracts the fully qualified constant name from a receiver node
    # Returns nil if the receiver is not a constant
    # Strips leading '::' to normalize absolute constant paths (::Chip::Service → Chip::Service)
    def constant_name_from(receiver)
      case receiver
      when Prism::ConstantPathNode then receiver.full_name.delete_prefix('::')
      when Prism::ConstantReadNode then receiver.name.to_s
      end
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
      nil
    end
  end

  # Parses a Ruby file and finds all service class instantiations
  # Returns an array of hashes: { constant: "Module::Class" }
  def find_instantiations_in_file(file_path)
    result = Prism.parse_file(file_path)

    Rails.logger.warn("Syntax errors in #{file_path}: #{result.errors}") unless result.success?

    return [] unless result.value

    finder = InstantiationFinder.new(SERVICE_SUFFIXES, @excluded_classes)
    result.value.accept(finder) # initiate visitor pattern traversal of the AST
    finder.instantiations.uniq { |i| i[:constant] }
  end

  # Chain Tracing (Recursive w Cycle Detection)

  # Traces a service instantiation to its ultimate external dependency
  # Returns an array of chain hashes
  def trace_chain(constant_name:, source_file:, visited:, chain_so_far:)
    current_chain = chain_so_far + [constant_name]

    # Step 1: Check if this constant is a known upstream service
    classified = classify_known_upstream(constant_name, current_chain)
    return classified if classified

    # Step 2: Resolve the constant to a file and follow its dependencies
    resolve_and_trace(constant_name, source_file, visited, current_chain)
  end

  # Returns a chain result if the constant is a known external service, nil if it
  # should be resolved further. Mobile:: classes are always traced through.
  #
  # NOTE: Short circuits when known upstream found, deeper calls inside matched services
  # are never discovered.
  # TODO: script classifies AND continues tracing.
  def classify_known_upstream(constant_name, current_chain)
    is_internal_class = constant_name.start_with?('Mobile::')
    return nil if is_internal_class

    upstream_group = classify_upstream(constant_name)
    return nil unless upstream_group

    [{
      path: current_chain,
      upstream_service: upstream_group
    }]
  end

  # Resolves a constant to a file, parses it, and recursively traces
  # any service instantiations found inside
  def resolve_and_trace(constant_name, source_file, visited, current_chain)
    resolved_file = resolve_constant_to_file(constant_name, source_file)

    unless resolved_file
      record_unclassified(constant_name, source_file)
      return []
    end

    # Cycle detection: don't visit the same file twice in one chain
    return [] if visited.include?(resolved_file)

    visited_with_current = visited | Set[resolved_file]
    deeper_instantiations = find_instantiations_in_file(resolved_file)

    return classify_leaf_node(constant_name, source_file, current_chain) if deeper_instantiations.empty?

    follow_deeper_chains(deeper_instantiations, resolved_file, visited_with_current, current_chain, constant_name)
  end

  # Classifies a leaf node (no deeper service calls) by checking upstream config
  # and ancestry. Records as unclassified if neither matches
  def classify_leaf_node(constant_name, source_file, current_chain)
    fallback_group = classify_upstream(constant_name)
    return [{ path: current_chain, upstream_service: fallback_group }] if fallback_group

    ancestry_result = classify_by_ancestry(constant_name)
    return [{ path: current_chain, upstream_service: ancestry_result[:upstream_service] }] if ancestry_result

    record_unclassified(constant_name, source_file, 'no deeper service calls and not in config')
    []
  end

  # Follows deeper instantiations found in a resolved file, falling back
  # to ancestry classification if all composition traces lead to dead ends.
  def follow_deeper_chains(deeper_instantiations, resolved_file, visited, current_chain, constant_name)
    downstream_chains = deeper_instantiations.flat_map do |inst|
      trace_chain(
        constant_name: inst[:constant],
        source_file: resolved_file,
        visited:,
        chain_so_far: current_chain
      )
    end

    return downstream_chains unless downstream_chains.empty?

    ancestry_result = classify_by_ancestry(constant_name)
    return [{ path: current_chain, upstream_service: ancestry_result[:upstream_service] }] if ancestry_result

    []
  end

  # Controller Inheritance — resolves dependencies inherited from parent controllers

  # Walks the controller's superclass chain to find inherited service instantiations.
  # Used when a controller has no direct .new/.build calls but inherits a service
  # method (e.g., `def client`) from a parent controller.
  # Returns an array of instantiation hashes or an empty array.
  def find_inherited_instantiations(controller_path)
    controller_class = controller_class_from_path(controller_path)
    return [] unless controller_class

    ancestor_source_files(controller_class).each do |file|
      instantiations = find_instantiations_in_file(file)
      return instantiations unless instantiations.empty?
    end

    []
  end

  # Returns source file paths for each superclass that lives within the vets-api app.
  # Stops when the ancestry leaves the application boundary (e.g., enters Rails/gem code).
  def ancestor_source_files(klass)
    files = []
    klass = klass.superclass
    while klass
      file, _line = Module.const_source_location(klass.name)
      break unless file&.start_with?(VETS_API_ROOT)

      files << file
      klass = klass.superclass
    end
    files
  end

  # Resolves a controller file path to its Ruby class using Zeitwerk autoloading.
  # Returns the class or nil if it cannot be resolved or is not a Class (e.g., modules/concerns).
  def controller_class_from_path(controller_path)
    # Convert file path to constant name using Zeitwerk conventions:
    # app/controllers/mobile/v0/folders_controller.rb -> Mobile::V0::FoldersController
    relative = controller_path.sub(%r{.*/app/controllers/}, '')
    const_name = relative.delete_suffix('.rb').camelize
    resolved = Object.const_get(const_name)
    resolved.is_a?(Class) ? resolved : nil
  rescue NameError
    nil
  end

  # Service Classification — maps service constants to upstream groups

  # Checks if a constant matches a known upstream service group from upstream_services.yml.
  # Returns the group name (ex: "VAOS") or nil if not found
  def classify_upstream(constant_name)
    @upstream_groups.each do |prefix, group|
      return group if constant_name.start_with?(prefix)
    end
    nil
  end

  # Walks the Ruby inheritance chain (via .superclass) to find a known upstream.
  # Returns { upstream_service: "VAOS", ancestor: "VAOS::SessionService" } or nil
  # Since Rails is already booted use runtime reflection instead of AST parsing
  MAX_ANCESTRY_DEPTH = 10

  def classify_by_ancestry(constant_name)
    klass = Object.const_get(constant_name)
    depth = 0

    while (klass = klass.superclass)
      depth += 1
      break if depth > MAX_ANCESTRY_DEPTH
      break if [Object, BasicObject].include?(klass)

      group = classify_upstream(klass.name)
      return { upstream_service: group, ancestor: klass.name } if group
    end

    nil
  rescue NameError
    nil
  end

  # Resolution & Output

  # Resolves constant name to its source file using Rails' Zeitwerk autoloader
  # Returns the file path or nil if the constant cannot be resolved and will be unresolved
  def resolve_constant_to_file(constant_name, _referencing_file)
    Object.const_get(constant_name)
    file, _line = Module.const_source_location(constant_name)
    file
  rescue NameError
    nil
  end

  # Records a constant that couldn't be resolved or classified.
  def record_unclassified(constant_name, source_file, reason = 'no matching file found')
    relative_path = source_file.sub("#{MOBILE_ROOT}/", '')
    # For files outside the mobile module, make path relative to vets-api root
    outside_mobile_module = relative_path == source_file
    relative_path = source_file.sub("#{VETS_API_ROOT}/", '') if outside_mobile_module

    @unresolved << {
      constant: constant_name,
      referenced_from: relative_path,
      reason:
    }
  end

  # Infer human readable feature name from a controller file path
  # app/controllers/mobile/v0/appointments_controller.rb -> "Appointments"
  def feature_name_from_path(relative_path)
    File.basename(relative_path, '.rb')
        .delete_suffix('_controller')
        .tr('_', ' ')
        .split.map(&:capitalize).join(' ')
  end

  def output_json(chains)
    output = {
      dependency_chains: chains.sort_by { |chain| chain[:feature] },
      unresolved: @unresolved.uniq { |u| u[:constant] }
    }

    json = JSON.pretty_generate(output)
    if @output_file
      File.write(@output_file, json)
    else
      $stdout.puts json
    end
  end
end

if $PROGRAM_NAME == __FILE__
  output_index = ARGV.index('--output')
  output_file = output_index ? ARGV[output_index + 1] : nil

  DiscoverUpstreamChains.new(output_file:).run
end
