require 'rdf/nquads'

module JSON::LD
  module FromRDF
    include Utils

    ##
    # Generate a JSON-LD array representation from an array of `RDF::Statement`.
    # Representation is in expanded form
    #
    # @param [Array<RDF::Statement>, RDF::Enumerable] input
    # @return [Array<Hash>] the JSON-LD document in normalized form
    def from_statements(input)
      default_graph = {:node_map => {}, :listMap => {}, :name => '@default'}
      graph_map = {'@default' => default_graph}

      value = nil
      ec = Context.new

      # Create a map for node to object representation

      # For each triple in input
      input.each do |statement|
        debug("statement") { statement.to_nquads.chomp}

        subject = ec.expand_iri(statement.subject).to_s
        name = statement.context ? ec.expand_iri(statement.context).to_s : '@default'
        
        # Create a graph entry as needed
        graph = graph_map[name] ||= {:node_map => {}, :listMap => {}, :name => name}
        
        case statement.predicate
        when RDF.first
          # If property is rdf:first,
          # create a new entry in _listMap_ for _name_ and _subject_ and an array value
          # containing the object representation and continue to the next statement.
          list_map = graph[:listMap]
          entry = list_map[subject] ||= {}
          object_rep = ec.expand_value(nil, statement.object, @options)
          entry[:first] = object_rep
          debug("rdf:first") { "save entry for #{subject.inspect} #{entry.inspect}"}
          next
        when RDF.rest
          # If property is rdf:rest,
          # and object is a blank node,
          # create a new entry in _restMap_ for _name_ and _subject_ and a value being the
          # result of IRI expansion on the object and continue to the next statement.
          next unless statement.object.is_a?(RDF::Node)

          list_map = graph[:listMap]
          entry = list_map[subject] ||= {}

          object_rep = ec.expand_iri(statement.object).to_s
          entry[:rest] = object_rep
          debug("rdf:rest") { "save entry for #{subject.inspect} #{entry.inspect}"}
          next
        end

        # Add entry to default graph for name unless it is @default
        default_graph[:node_map][name] ||= {'@id' => name} unless name == '@default'
        
        # Get value from graph nodes for subject, initializing it to a new node declaration for subject if it does not exist
        debug("@id") { "new subject: #{subject}"} unless graph[:node_map].has_key?(subject)
        value = graph[:node_map][subject] ||= {'@id' => subject}

        # If property is http://www.w3.org/1999/02/22-rdf-syntax-ns#type
        # and the useRdfType option is not true
        if statement.predicate == RDF.type && !@options[:useRdfType]
          object = ec.expand_iri(statement.object).to_s
          debug("@type") { object.inspect}
          # append the string representation of object to the array value for the key @type, creating
          # an entry if necessary
          (value['@type'] ||= []) << object
        # FIXME: 3.7) If object is a typed literal and the useNativeTypes option is set to true:
        elsif statement.object == RDF.nil
          # Otherwise, if object is http://www.w3.org/1999/02/22-rdf-syntax-ns#nil, let
          # key be the string representation of predicate. Set the value
          # for key to an empty @list representation {"@list": []}
          key = ec.expand_iri(statement.predicate).to_s
          (value[key] ||= []) << {"@list" => []}
        else
          # Otherwise, let key be the string representation of predicate and 
          # let object representation be object represented in expanded form as 
          # described in Value Expansion.
          key = ec.expand_iri(statement.predicate).to_s
          object = ec.expand_value(key, statement.object, @options)
          if blank_node?(object)
            # if object is an Unnamed Node, set as the head element in the list_map
            # entry for object
            list_map = graph[:listMap]
            entry = list_map[object['@id']] ||= {}
            entry[:head] = object
            debug("bnode") { "save entry #{entry.inspect}"}
          end

          debug("key/value") { "key: #{key}, :value #{object.inspect}"}
          
          # append the object object representation to the array value for key, creating
          # an entry if necessary
          (value[key] ||= []) << object
        end
      end

      # Build lists for each graph
      graph_map.each do |name, graph|
        graph[:listMap].each do |subject, entry|
          debug("listMap(#{name}, #{subject})") { entry.inspect}
          if entry.has_key?(:head) && entry.has_key?(:first)
            debug("@list") { "List head for #{subject.inspect} in #{name.inspect}: #{entry.inspect}"}
            value = entry[:head]
            value.delete('@id')
            list = value['@list'] = [entry[:first]].compact
            
            while rest = entry.fetch(:rest, nil)
              entry = graph[:listMap][rest]
              debug(" => ") { "add #{entry.inspect}"}
              raise JSON::LD::ProcessingError, "list entry missing rdf:first" unless entry.has_key?(:first)
              list << entry[:first]
            end
          end
        end
      end

      # Build graphs in @id order
      debug("graph_map") {graph_map.to_json(JSON_STATE)}
      array = default_graph[:node_map].keys.sort.map do |subject|
        entry = default_graph[:node_map][subject]
        debug("=> default") {entry.to_json(JSON_STATE)}
        
        # If subject is a named graph, add serialized subject defintions
        if graph_map.has_key?(subject) && !subject.empty?
          entry['@graph'] = graph_map[subject][:node_map].keys.sort.map do |s|
            debug("=> #{s.inspect}")
            graph_map[subject][:node_map][s]
          end
        end
        
        debug("default graph") {entry.inspect}
        entry
      end

      # Return array as the graph representation.
      debug("fromRDF") {array.to_json(JSON_STATE)}
      array
    end
  end
end
