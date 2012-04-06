require 'open-uri'
require 'json/ld/expand'
require 'json/ld/compact'
require 'json/ld/frame'
#require 'json/ld/normalize'
require 'json/ld/triples'
require 'json/ld/from_triples'

module JSON::LD
  ##
  # A JSON-LD processor implementing the JsonLdProcessor interface.
  #
  # This API provides a clean mechanism that enables developers to convert JSON-LD data into a a variety of output formats that
  # are easier to work with in various programming languages. If a JSON-LD API is provided in a programming environment, the
  # entirety of the following API must be implemented.
  #
  # @see http://json-ld.org/spec/latest/json-ld-api/#the-application-programming-interface
  # @author [Gregg Kellogg](http://greggkellogg.net/)
  class API
    include Expand
    include Compact
    include Triples
    include FromTriples
    include Frame
    #include Normalize

    attr_accessor :value
    attr_accessor :context

    ##
    # Initialize the API, reading in any document and setting global options
    #
    # @param [#read, Hash, Array] input
    # @param [IO, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param [Hash] options
    # @yield [api]
    # @yieldparam [API]
    def initialize(input, context, options = {}, &block)
      @options = options
      @value = input.dup if input
      @value = JSON.parse(@value.read) if @value.respond_to?(:read)
      @context = EvaluationContext.new(options)
      @context = @context.parse(context) if context
      
      if block_given?
        case block.arity
          when 0 then instance_eval(&block)
          else block.call(self)
        end
      end
    end
    
    ##
    # Expands the given input according to the steps in the Expansion Algorithm. The input must be copied, expanded and returned
    # if there are no errors. If the expansion fails, an appropriate exception must be thrown.
    #
    # @param [#read, Hash, Array] input
    #   The JSON-LD object to copy and perform the expansion upon.
    # @param [IO, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    # @raise [InvalidContext]
    # @return [Hash, Array]
    #   The expanded JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#expansion-algorithm
    def self.expand(input, context = nil, options = {})
      result = nil
      API.new(input, context, options) do |api|
        result = api.expand(api.value, nil, api.context)
      end
      result.is_a?(Array) ? result : [result]
    end

    ##
    # Compacts the given input according to the steps in the Compaction Algorithm. The input must be copied, compacted and
    # returned if there are no errors. If the compaction fails, an appropirate exception must be thrown.
    #
    # If no context is provided, the input document is compacted using the top-level context of the document
    #
    # @param [IO, Hash, Array] input
    #   The JSON-LD object to copy and perform the compaction upon.
    # @param [IO, Hash, Array] context
    #   The base context to use when compacting the input.
    # @param [Boolean] optimize (false)
    #   Perform further optimmization of the compacted output.
    #   (Presently, this is a noop).
    # @param  [Hash{Symbol => Object}] options
    # @raise [InvalidContext, ProcessingError]
    # @return [Hash]
    #   The compacted JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#compaction-algorithm
    def self.compact(input, context, optimize = false, options = {})
      expanded = result = nil

      # 1) Perform the Expansion Algorithm on the JSON-LD input.
      #    This removes any existing context to allow the given context to be cleanly applied.
      API.new(input, nil, options) do |api|
        expanded = api.expand(api.value, nil, api.context)

        # x) If no context provided, use context from input document
        context ||= api.value.fetch('@context', nil)
      end

      API.new(expanded, context, options) do |api|
        result = api.compact(api.value, nil)

        # xxx) Add the given context to the output
        result = case result
        when Hash then api.context.serialize.merge(result)
        when Array
          kwgraph = api.context.compact_iri('@graph', :quiet => true)
          api.context.serialize.merge(kwgraph => result)
        when String
          kwid = api.context.compact_iri('@id', :quiet => true)
          api.context.serialize.merge(kwid => result)
        end
      end
      result
    end

    ##
    # Frames the given input using the frame according to the steps in the Framing Algorithm. The input is used to build the
    # framed output and is returned if there are no errors. If there are no matches for the frame, null must be returned.
    # Exceptions must be thrown if there are errors.
    #
    # @param [IO, Hash, Array] input
    #   The JSON-LD object to copy and perform the framing on.
    # @param [IO, Hash, Array] frame
    #   The frame to use when re-arranging the data.
    # @param  [Hash{Symbol => Object}] options
    # @option options [Boolean] :embed (true)
    #   a flag specifying that objects should be directly embedded in the output,
    #   instead of being referred to by their IRI.
    # @option options [Boolean] :explicit (false)
    #   a flag specifying that for properties to be included in the output,
    #   they must be explicitly declared in the framing context.
    # @option options [Boolean] :omitDefault (false)
    #   a flag specifying that properties that are missing from the JSON-LD
    #   input should be omitted from the output.
    # @raise [InvalidFrame]
    # @return [Hash]
    #   The framed JSON-LD document
    # @see http://json-ld.org/spec/latest/json-ld-api/#framing-algorithm
    def self.frame(input, frame, options = {})
      result = nil
      match_limit = 0
      framing_state = {
        :embed       => true,
        :explicit    => false,
        :omitDefault => false,
        :embeds      => {},
      }
      framing_state[:embed] = options[:embed] if options.has_key?(:embed)
      framing_state[:explicit] = options[:explicit] if options.has_key?(:explicit)
      framing_state[:omitDefault] = options[:omitDefault] if options.has_key?(:omitDefault)

      # de-reference frame to create the framing object
      frame = frame.respond_to?(:read) ? JSON.parse(frame.read) : frame

      # Expand frame to simplify processing
      expanded_frame = API.expand(frame)
      
      # Expand input to simplify processing
      expanded_input = API.expand(input)

      # Initialize input using frame as context
      API.new(expanded_input, nil, options) do
        debug(".frame") {"context from frame: #{context.inspect}"}
        debug(".frame") {"expanded frame: #{expanded_frame.to_json(JSON_STATE)}"}
        debug(".frame") {"expanded input: #{value.to_json(JSON_STATE)}"}

        # Get framing subjects from expanded input, replacing Blank Node identifiers as necessary
        @subjects = Hash.ordered
        depth {get_framing_subjects(@subjects, value, BlankNodeNamer.new("t"))}
        debug(".frame") {"subjects: #{@subjects.to_json(JSON_STATE)}"}

        result = []
        frame(framing_state, @subjects.keys, expanded_frame[0], result, nil)
        debug(".frame") {"result: #{result.inspect}"}
        
        # Initalize context from frame
        @context = depth {@context.parse(frame['@context'])}
        # Compact result
        compacted = depth {compact(result, nil)}
        
        # xxx) Add the given context to the output
        result = case compacted
        when Hash then [context.serialize.merge(compacted)]
        when Array
          ctx = context.serialize
          compacted.map do |o|
            o = {"@id" => o} if o.is_a?(String)
            ctx.merge(o)
          end
        when String then [context.serialize.merge("@id" => compacted)]
        end
        
        result = cleanup_null(result)
      end
      result
    end

    ##
    # Normalizes the given input according to the steps in the Normalization Algorithm. The input must be copied, normalized and
    # returned if there are no errors. If the compaction fails, null must be returned.
    #
    # @param [IO, Hash, Array] input
    #   The JSON-LD object to copy and perform the normalization upon.
    # @param [IO, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    # @raise [InvalidContext]
    # @return [Array<Hash>]
    #   The normalized JSON-LD document
    def self.normalize(input, object, context = nil, options = {})
    end

    ##
    # Processes the input according to the RDF Conversion Algorithm, calling the provided tripleCallback for each triple generated.
    #
    # Note that for Ruby, if the tripleCallback is not provided, it will be yielded
    #
    # @param [IO, Hash, Array] input
    #   The JSON-LD object to process when outputting triples.
    # @param [IO, Hash, Array] context
    #   An external context to use additionally to the context embedded in input when expanding the input.
    # @param  [Hash{Symbol => Object}] options
    # @raise [InvalidContext]
    # @yield statement
    # @yieldparam [RDF::Statement] statement
    def self.toTriples(input, tripleCallback = nil, context = nil, options = {})
      # 1) Perform the Expansion Algorithm on the JSON-LD input.
      #    This removes any existing context to allow the given context to be cleanly applied.
      expanded = expand(input, context, options)

      API.new(expanded, nil, options) do |api|
        # Start generating triples
        api.triples("", api.value, nil, nil) do |statement|
          tripleCallback.call(statement) if tripleCallback
          yield statement if block_given?
        end
      end
    end
    
    ##
    # Take an ordered list of RDF::Statements and turn them into a JSON-LD document.
    #
    # @param [Array<RDF::Statement>] input
    # @param  [Hash{Symbol => Object}] options
    # @return [Array<Hash>] the JSON-LD document in expanded form
    def self.fromTriples(input, options = {})
      result = nil

      API.new(nil, nil, options) do |api|
        result = api.from_triples(input)
      end
      result
    end
  end
end

