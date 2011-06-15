module Glitr

  class Base
    include Comparable

    attr_accessor :id, :attributes

    def initialize(id, attributes)
      self.id, self.attributes = id, attributes
    end

    class << self
      def entity_type
        @entity_type ||= name.split("::").last
      end

      def entity_type=(type)
        @entity_type = type
      end
      alias :set_entity_type :entity_type=

      def namespace
        @namespace
      end

      def namespace=(ns)
        @namespace = ns
      end
      alias :set_namespace :namespace=

      def all(conditions = {})
        query = <<-QUERY
          PREFIX :   <http://metrumrg.com/metamodl/>
          PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
          PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

          SELECT DISTINCT ?_subject ?_predicate ?_object
          WHERE {
           ?#{entity_type} rdf:type :#{entity_type} .

           #{ build_filters entity_type, conditions  }

           LET ( ?_subject := ?#{entity_type} ) .
           ?_subject ?_predicate ?_object .
          }
        QUERY

        subjects = connection.fetch_subjects(query)
        build_all(subjects)
      end

      def select(attributes, conditions = {})
        query = <<-QUERY
          PREFIX :   <http://metrumrg.com/metamodl/>
          PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
          PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

          SELECT DISTINCT #{ attributes.map {|attr| "?#{attr}"}.join(' ') }
          WHERE {
            ?#{entity_type} rdf:type :#{entity_type} .
            #{ build_bindings entity_type, attributes }
            #{ build_filters  entity_type, conditions }
          }
        QUERY

        result = connection.fetch(query)
      end

      def count(conditions = {})
        query = <<-QUERY
          PREFIX :   <http://metrumrg.com/metamodl/>
          PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
          PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

          SELECT (count(distinct ?uuid) as ?count)
          WHERE {

            ?#{entity_type} rdf:type :#{entity_type};
                    :uuid ?uuid .
            #{ build_filters entity_type, conditions }
          }
        QUERY

        result = connection.fetch(query)
        result.first && result.first['count'].to_i
      end

      def columns
        return @columns if defined?(@columns)

        namespace = "http://metrumrg.com/metamodl/"
        query = <<-QUERY
          PREFIX :   <#{namespace}>
          PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
          PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

          SELECT DISTINCT ?column
          WHERE {

            ?#{entity_type} rdf:type :#{entity_type};
                    ?column ?_ .
          }
        QUERY

        result = connection.fetch(query)
        @columns = result.
          select {|row| row['column'].match(/^#{namespace}/)}.
          map {|row| row['column'].sub(/^#{namespace}/,"") }
      end


      def build_filters(entity_type, conditions)
        conditions.reject! {|attr, value| value.blank?}

        bindings = build_bindings entity_type, conditions.keys
        filters = conditions.map{|attr, *values| "FILTER ( ?#{attr} in (#{values.flatten.map {|val| '"'+val+'"'}.join(',') }) ) ." }.join("\n")
        [bindings, filters].join("\n")
      end

      def build_bindings(entity_type, attributes)
        attributes.map{|attr| "OPTIONAL { ?#{entity_type} :#{attr} ?#{attr} . }" }.join("\n")
      end

      private

      def connection
        @connection ||= Glitr::Connection.new(:service => "metamodl_#{Rails.env}")
      end

      def build_all(entities)
        entities.map {|id, attrs| new(id, attrs) }
      end
    end

    def [](attr)
      attributes[namespaced_key(attr)]
    end

    def method_missing(method, *params)
      key = namespaced_key(method)

      if attributes.has_key?(key)
        return attributes[key] 
      else
        super
      end
    end

    def <=>(other)
      self.attributes <=> other.attributes
    end

    private

    def namespaced_key(key)
      "#{self.class.namespace}/#{key}"
    end

  end

end
